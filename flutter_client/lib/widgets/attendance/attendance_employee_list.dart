import 'package:flutter/material.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

import '../../theme/sbox_tokens.dart';
import '../hrm_page_chrome.dart';

/// Bỏ dấu tiếng Việt + chữ thường — tìm «nguyen» ra «Nguyễn».
String attendanceFoldVi(String s) {
  const from = 'àáạảãâầấậẩẫăằắặẳẵèéẹẻẽêềếệểễìíịỉĩòóọỏõôồốộổỗơờớợởỡùúụủũưừứựửữỳýỵỷỹđ';
  const to = 'aaaaaaaaaaaaaaaaaeeeeeeeeeeeiiiiiooooooooooooooooouuuuuuuuuuuyyyyyd';
  final b = StringBuffer();
  for (final ch in s.toLowerCase().split('')) {
    final i = from.indexOf(ch);
    b.write(i >= 0 ? to[i] : ch);
  }
  return b.toString();
}

String attendanceInitials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first[0].toUpperCase();
  return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
}

/// Một mẩu số liệu trên dòng phụ («3 vắng» tô đỏ…).
class AttendanceMetricPart {
  const AttendanceMetricPart(this.text, {this.color});
  final String text;
  final Color? color;
}

/// Dòng NV gọn (~60dp) cho danh sách tổng hợp trên điện thoại.
class AttendanceEmployeeRow extends StatelessWidget {
  const AttendanceEmployeeRow({
    super.key,
    required this.name,
    required this.parts,
    required this.primary,
    this.primaryColor,
    this.hourly = false,
    this.onTap,
  });

  final String name;
  final List<AttendanceMetricPart> parts;

  /// Số chính bên phải: «22/26 công» hoặc «48,5 giờ» (lương giờ).
  final String primary;
  final Color? primaryColor;
  final bool hourly;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: SboxColors.slate100)),
          ),
          child: Row(children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: HrmPageChrome.primaryNavy.withValues(alpha: 0.10),
              child: Text(attendanceInitials(name),
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: HrmPageChrome.primaryNavy)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(
                    child: Text(tr(name),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: SboxColors.slate900)),
                  ),
                ]),
                const SizedBox(height: 2),
                Text.rich(
                  TextSpan(children: [
                    // Lương theo giờ: ghi ở đầu dòng phụ (để trên dòng tên làm tên bị cắt trên điện thoại).
                    if (hourly) ...[
                      TextSpan(
                        text: tr('Lương giờ'),
                        style: const TextStyle(color: HrmPageChrome.chipMid, fontWeight: FontWeight.w700),
                      ),
                      if (parts.isNotEmpty) const TextSpan(text: ' · '),
                    ],
                    for (final (i, p) in parts.indexed) ...[
                      if (i > 0) const TextSpan(text: ' · '),
                      TextSpan(
                        text: tr(p.text),
                        style: p.color == null ? null : TextStyle(color: p.color, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: SboxColors.slate600),
                ),
              ]),
            ),
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 120),
              child: Text(tr(primary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: primaryColor ?? SboxColors.slate900)),
            ),
            const Icon(Icons.chevron_right, color: SboxColors.slate300, size: 20),
          ]),
        ),
      ),
    );
  }
}

/// Tiêu đề nhóm trong danh sách («Tính theo công», «Lương theo giờ»).
class AttendanceGroupHeader extends StatelessWidget {
  const AttendanceGroupHeader(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        color: SboxColors.slate50,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
        child: Text(tr(text),
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: SboxColors.slate600)),
      );
}

class AttendanceListFilter {
  const AttendanceListFilter(this.key, this.label, this.count, {this.danger = false});
  final String key;
  final String label;
  final int count;
  final bool danger;
}

/// Đầu danh sách NV: tiêu đề + sắp xếp, ô tìm, chip lọc (bấm chip → danh sách lọc ngay).
class AttendanceEmployeeListToolbar extends StatelessWidget {
  const AttendanceEmployeeListToolbar({
    super.key,
    required this.total,
    required this.sortKey,
    required this.sortLabels,
    required this.onSort,
    required this.searchController,
    required this.onQuery,
    required this.filters,
    required this.filterKey,
    required this.onFilter,
  });

  final int total;
  final String sortKey;
  final Map<String, String> sortLabels;
  final ValueChanged<String> onSort;
  final TextEditingController searchController;
  final ValueChanged<String> onQuery;
  final List<AttendanceListFilter> filters;
  final String filterKey;
  final ValueChanged<String> onFilter;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(
          child: Text(tr('Nhân viên ($total)'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: SboxColors.slate900)),
        ),
        PopupMenuButton<String>(
          tooltip: tr('Sắp xếp'),
          initialValue: sortKey,
          onSelected: onSort,
          itemBuilder: (_) => [
            for (final e in sortLabels.entries) PopupMenuItem(value: e.key, child: Text(tr(e.value))),
          ],
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.sort, size: 18, color: HrmPageChrome.primaryNavy),
              const SizedBox(width: 4),
              Text(tr(sortLabels[sortKey] ?? ''),
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: HrmPageChrome.primaryNavy)),
            ]),
          ),
        ),
      ]),
      if (total > 6) ...[
        const SizedBox(height: 6),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: searchController,
          builder: (_, v, __) => TextField(
            controller: searchController,
            onChanged: onQuery,
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: Colors.white,
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: v.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        searchController.clear();
                        onQuery('');
                      },
                    ),
              hintText: tr('Tìm nhân viên…'),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
      ],
      const SizedBox(height: 6),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          for (final f in filters)
            if (f.key == 'all' || f.count > 0)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text(tr('${f.label} ${f.count}')),
                  selected: filterKey == f.key,
                  showCheckmark: false,
                  visualDensity: VisualDensity.compact,
                  labelStyle: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: filterKey == f.key
                        ? Colors.white
                        : (f.danger ? SboxColors.dangerText : SboxColors.slate700),
                  ),
                  selectedColor: f.danger ? SboxColors.danger : HrmPageChrome.primaryNavy,
                  onSelected: (_) => onFilter(f.key),
                ),
              ),
        ]),
      ),
    ]);
  }
}

/// Khung trắng bo góc cho danh sách dòng NV trong CustomScrollView.
Widget attendanceEmployeeListSliver(List<Widget Function()> builders, {String emptyText = 'Không có nhân viên phù hợp'}) {
  if (builders.isEmpty) {
    return SliverToBoxAdapter(
      child: Container(
        padding: const EdgeInsets.all(24),
        alignment: Alignment.center,
        child: Text(tr(emptyText), style: const TextStyle(color: SboxColors.slate500)),
      ),
    );
  }
  return DecoratedSliver(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: SboxColors.slate200),
    ),
    sliver: SliverPadding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, i) => builders[i](),
          childCount: builders.length,
        ),
      ),
    ),
  );
}
