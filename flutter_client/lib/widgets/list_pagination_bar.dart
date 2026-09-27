import 'package:flutter/material.dart';

import 'sbox/sbox_table.dart';

/// Footer phân trang (giữ API cũ) — hiển thị bằng thanh phân trang chuẩn [SboxPager].
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
    return SboxPager(
      page: currentPage,
      pageSize: pageSize,
      total: totalCount,
      pageSizes: pageSizeOptions,
      onPage: onPageChanged,
      onPageSize: onPageSizeChanged,
    );
  }
}
