import 'package:flutter/material.dart';

/// Footer phân trang client-side (dùng chung nhiều màn danh sách).
class ListPaginationBar extends StatelessWidget {
  final int currentPage;
  final int pageSize;
  final int totalCount;
  final List<int> pageSizeOptions;
  final ValueChanged<int> onPageChanged;
  final ValueChanged<int>? onPageSizeChanged;
  final bool showWhenSinglePage;

  const ListPaginationBar({
    super.key,
    required this.currentPage,
    required this.pageSize,
    required this.totalCount,
    this.pageSizeOptions = const [20, 50, 100, 200],
    required this.onPageChanged,
    this.onPageSizeChanged,
    this.showWhenSinglePage = false,
  });

  int get totalPages => (totalCount / pageSize).ceil().clamp(1, 99999);

  @override
  Widget build(BuildContext context) {
    if (!showWhenSinglePage && totalPages <= 1 && totalCount <= pageSize) {
      return const SizedBox.shrink();
    }

    final start = totalCount > 0 ? (currentPage - 1) * pageSize + 1 : 0;
    final end = (currentPage * pageSize).clamp(0, totalCount);
    final primary = Theme.of(context).primaryColor;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 8,
        children: [
          Text(
            totalCount > 0
                ? 'Hiển thị $start-$end / $totalCount'
                : 'Không có dữ liệu',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
          if (onPageSizeChanged != null)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Hiển thị:',
                    style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                const SizedBox(width: 8),
                Container(
                  height: 34,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFAFAFA),
                    border: Border.all(color: const Color(0xFFE4E4E7)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<int>(
                      value: pageSize,
                      isDense: true,
                      style:
                          TextStyle(fontSize: 13, color: Colors.grey[800]),
                      items: pageSizeOptions
                          .map((s) => DropdownMenuItem(
                                value: s,
                                child: Text('$s'),
                              ))
                          .toList(),
                      onChanged: (v) {
                        if (v != null) onPageSizeChanged!(v);
                      },
                    ),
                  ),
                ),
              ],
            ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.first_page, size: 20),
                onPressed:
                    currentPage > 1 ? () => onPageChanged(1) : null,
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                icon: const Icon(Icons.chevron_left, size: 20),
                onPressed: currentPage > 1
                    ? () => onPageChanged(currentPage - 1)
                    : null,
                visualDensity: VisualDensity.compact,
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: primary,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$currentPage / $totalPages',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right, size: 20),
                onPressed: currentPage < totalPages
                    ? () => onPageChanged(currentPage + 1)
                    : null,
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                icon: const Icon(Icons.last_page, size: 20),
                onPressed: currentPage < totalPages
                    ? () => onPageChanged(totalPages)
                    : null,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Cắt danh sách theo trang (client pagination).
List<T> paginatedSlice<T>(List<T> items, int page, int pageSize) {
  if (items.isEmpty) return items;
  final start = (page - 1) * pageSize;
  if (start >= items.length) return [];
  final end = (start + pageSize).clamp(0, items.length);
  return items.sublist(start, end);
}
