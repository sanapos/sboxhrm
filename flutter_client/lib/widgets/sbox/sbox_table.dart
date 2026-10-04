import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../l10n/app_tr.dart';
import '../../theme/sbox_tokens.dart';
import 'sbox_basics.dart';

/// Cột của [SboxDataTable].
class SboxColumn<T> {
  const SboxColumn({
    required this.label,
    this.text,
    this.cell,
    this.width,
    this.flex = 1,
    this.minWidth = 96,
    this.numeric = false,
    this.align,
    this.sortValue,
    this.maxLines = 1,
    this.primary = false,
    this.hideOnMobile = false,
  }) : assert(text != null || cell != null);

  final String label;
  /// Nội dung dạng chữ — tự cắt "…" và hiện đầy đủ khi rê chuột.
  final String Function(T row)? text;
  /// Nội dung tùy biến (nhãn trạng thái, nút…).
  final Widget Function(T row)? cell;
  /// Bề rộng cố định (px). null = co giãn theo [flex].
  final double? width;
  final int flex;
  final double minWidth;
  /// Cột số / tiền: căn phải, chữ số đều nhau.
  final bool numeric;
  final TextAlign? align;
  /// Có giá trị → bấm tiêu đề để sắp xếp.
  final Comparable<Object?>? Function(T row)? sortValue;
  final int maxLines;
  /// Cột chính: làm tiêu đề thẻ khi xem trên điện thoại.
  final bool primary;
  final bool hideOnMobile;

  double get _min => width ?? minWidth;
}

/// Bảng dữ liệu chuẩn SBOX:
/// - tiêu đề nền nhạt, dòng cao đều, rê chuột tô nhẹ, chữ dài tự cắt "…" + chú thích
/// - bấm tiêu đề để sắp xếp; cột số căn phải
/// - hẹp hơn tổng cột → cuộn ngang; điện thoại → tự chuyển dạng thẻ
/// - phân trang sẵn (client-side) hoặc để trang ngoài tự phân trang
class SboxDataTable<T> extends StatefulWidget {
  const SboxDataTable({
    super.key,
    required this.columns,
    required this.rows,
    this.onRowTap,
    this.rowActions,
    this.loading = false,
    this.emptyTitle = 'Chưa có dữ liệu',
    this.emptyMessage,
    this.emptyAction,
    this.pageSize = 20,
    this.paginate = true,
    this.dense = false,
    this.mobileCards = true,
    this.selectedRow,
  });

  final List<SboxColumn<T>> columns;
  final List<T> rows;
  final ValueChanged<T>? onRowTap;
  /// Nút thao tác cuối dòng (sửa / xóa…).
  final Widget Function(T row)? rowActions;
  final bool loading;
  final String emptyTitle;
  final String? emptyMessage;
  final Widget? emptyAction;
  final int pageSize;
  final bool paginate;
  final bool dense;
  final bool mobileCards;
  final T? selectedRow;

  @override
  State<SboxDataTable<T>> createState() => _SboxDataTableState<T>();
}

class _SboxDataTableState<T> extends State<SboxDataTable<T>> {
  int? _sortCol;
  bool _asc = true;
  int _page = 1;
  late int _pageSize = widget.pageSize;
  int? _hover;
  final _hScroll = ScrollController();

  @override
  void didUpdateWidget(covariant SboxDataTable<T> old) {
    super.didUpdateWidget(old);
    // Lọc / tải lại → về trang 1; thêm / xóa đúng 1 dòng (sửa tại chỗ) → giữ trang đang xem
    // (trước đây xóa 1 dòng ở trang 3 bị nhảy về trang 1). Trang vượt quá số trang được kẹp lúc build.
    final diff = (old.rows.length - widget.rows.length).abs();
    if (diff > 1) _page = 1;
  }

  @override
  void dispose() {
    _hScroll.dispose();
    super.dispose();
  }

  List<T> get _sorted {
    final list = List<T>.of(widget.rows);
    final c = _sortCol == null ? null : widget.columns[_sortCol!];
    if (c?.sortValue != null) {
      list.sort((a, b) {
        final va = c!.sortValue!(a);
        final vb = c.sortValue!(b);
        if (va == null && vb == null) return 0;
        if (va == null) return 1;
        if (vb == null) return -1;
        final r = va.compareTo(vb);
        return _asc ? r : -r;
      });
    }
    return list;
  }

  void _toggleSort(int i) {
    if (widget.columns[i].sortValue == null) return;
    setState(() {
      if (_sortCol == i) {
        _asc = !_asc;
      } else {
        _sortCol = i;
        _asc = true;
      }
      _page = 1; // thứ tự đổi → xem lại từ đầu
    });
  }

  @override
  Widget build(BuildContext context) {
    final all = _sorted;
    final total = all.length;
    final pages = math.max(1, (total / _pageSize).ceil());
    if (_page > pages) _page = pages;
    final visible = widget.paginate
        ? all.skip((_page - 1) * _pageSize).take(_pageSize).toList()
        : all;
    final mobile = widget.mobileCards && SboxBreakpoints.isMobile(context);

    Widget body;
    if (widget.loading && widget.rows.isEmpty) {
      body = const SboxLoading(message: 'Đang tải…');
    } else if (widget.rows.isEmpty) {
      body = SboxEmptyState(title: widget.emptyTitle, message: widget.emptyMessage, action: widget.emptyAction);
    } else if (mobile) {
      body = _buildCards(visible);
    } else {
      body = _buildGrid(visible);
    }

    return Container(
      decoration: const BoxDecoration(
        color: SboxColors.surface,
        borderRadius: SboxRadius.lgAll,
        border: Border.fromBorderSide(BorderSide(color: SboxColors.border)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (widget.loading && widget.rows.isNotEmpty) const LinearProgressIndicator(minHeight: 2),
        body,
        if (widget.paginate && total > 0)
          SboxPager(
            page: _page,
            pageSize: _pageSize,
            total: total,
            onPage: (p) => setState(() => _page = p),
            onPageSize: (s) => setState(() {
              _pageSize = s;
              _page = 1;
            }),
          ),
      ]),
    );
  }

  // ── Dạng bảng (máy tính / máy tính bảng) ──
  Widget _buildGrid(List<T> rows) {
    return LayoutBuilder(builder: (context, cons) {
      final cols = widget.columns;
      final actionsW = widget.rowActions == null ? 0.0 : 96.0;
      final minTotal = cols.fold<double>(0, (s, c) => s + c._min) + actionsW + SboxSpace.lg * 2;
      final tableW = math.max(cons.maxWidth, minTotal);
      final fixed = cols.where((c) => c.width != null).fold<double>(0, (s, c) => s + c.width!);
      final flexSum = cols.where((c) => c.width == null).fold<int>(0, (s, c) => s + c.flex);
      final free = math.max(0.0, tableW - SboxSpace.lg * 2 - actionsW - fixed);
      double w(SboxColumn<T> c) => c.width ?? math.max(c.minWidth, free * c.flex / math.max(1, flexSum));

      final rowH = widget.dense ? SboxSize.tableRowDense : SboxSize.tableRow;
      final header = Container(
        height: SboxSize.tableHeader,
        padding: const EdgeInsets.symmetric(horizontal: SboxSpace.lg),
        decoration: const BoxDecoration(
          color: SboxColors.slate50,
          border: Border(bottom: BorderSide(color: SboxColors.border)),
        ),
        child: Row(children: [
          for (var i = 0; i < cols.length; i++)
            SizedBox(width: w(cols[i]), child: _headerCell(i, cols[i])),
          if (actionsW > 0) SizedBox(width: actionsW),
        ]),
      );
      final body = Column(children: [
        for (var r = 0; r < rows.length; r++)
          MouseRegion(
            onEnter: (_) => setState(() => _hover = r),
            onExit: (_) => setState(() => _hover = null),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onRowTap == null ? null : () => widget.onRowTap!(rows[r]),
              child: Container(
                constraints: BoxConstraints(minHeight: rowH),
                padding: const EdgeInsets.symmetric(horizontal: SboxSpace.lg, vertical: 2),
                decoration: BoxDecoration(
                  color: rows[r] == widget.selectedRow
                      ? SboxColors.brand50
                      : (_hover == r ? SboxColors.slate50 : SboxColors.surface),
                  border: const Border(bottom: BorderSide(color: SboxColors.divider)),
                ),
                child: Row(children: [
                  for (final c in cols) SizedBox(width: w(c), child: _cell(c, rows[r])),
                  if (actionsW > 0)
                    SizedBox(
                      width: actionsW,
                      child: Align(alignment: Alignment.centerRight, child: widget.rowActions!(rows[r])),
                    ),
                ]),
              ),
            ),
          ),
      ]);
      final table = SizedBox(width: tableW, child: Column(children: [header, body]));
      if (tableW <= cons.maxWidth) return table;
      return Scrollbar(
        controller: _hScroll,
        thumbVisibility: true,
        child: SingleChildScrollView(controller: _hScroll, scrollDirection: Axis.horizontal, child: table),
      );
    });
  }

  Widget _headerCell(int i, SboxColumn<T> c) {
    final sortable = c.sortValue != null;
    final active = _sortCol == i;
    final label = Text(
      tr(c.label),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: c.numeric ? TextAlign.right : (c.align ?? TextAlign.left),
      style: TextStyle(
        fontSize: SboxType.caption,
        fontWeight: SboxType.semibold,
        color: active ? SboxColors.brand700 : SboxColors.textSecondary,
        letterSpacing: 0.2,
      ),
    );
    final content = Row(
      mainAxisAlignment: c.numeric ? MainAxisAlignment.end : MainAxisAlignment.start,
      children: [
        Flexible(child: label),
        if (sortable) ...[
          const SizedBox(width: 2),
          Icon(
            active ? (_asc ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded) : Icons.unfold_more_rounded,
            size: 14,
            color: active ? SboxColors.brand700 : SboxColors.slate400,
          ),
        ],
      ],
    );
    return Padding(
      padding: const EdgeInsets.only(right: SboxSpace.md),
      child: sortable
          ? InkWell(onTap: () => _toggleSort(i), borderRadius: SboxRadius.smAll, child: content)
          : content,
    );
  }

  Widget _cell(SboxColumn<T> c, T row) {
    Widget child;
    if (c.cell != null) {
      child = Align(alignment: c.numeric ? Alignment.centerRight : Alignment.centerLeft, child: c.cell!(row));
    } else {
      final s = c.text!(row);
      final t = Text(
        s,
        maxLines: c.maxLines,
        overflow: TextOverflow.ellipsis,
        textAlign: c.numeric ? TextAlign.right : (c.align ?? TextAlign.left),
        style: c.numeric
            ? SboxType.moneyStyle(size: SboxType.small).copyWith(fontWeight: SboxType.medium)
            : (c.primary ? SboxType.bodyStyle().copyWith(fontSize: SboxType.small, fontWeight: SboxType.medium) : SboxType.smallStyle(SboxColors.text)),
      );
      // Chữ dài: rê chuột xem đầy đủ.
      child = s.length > 18 ? Tooltip(message: s, child: t) : t;
    }
    return Padding(padding: const EdgeInsets.only(right: SboxSpace.md), child: child);
  }

  // ── Dạng thẻ (điện thoại) ──
  /// Thẻ điện thoại gọn (kiểu danh sách KiotViet):
  /// - hàng 1: cột chính (tên / mã) + số tiền đầu tiên bên phải
  /// - hàng 2: các cột chữ nối « · » (bỏ ô trống)
  /// - hàng 3: nhãn trạng thái / nút + các cột số còn lại dạng «Nhãn giá trị»
  /// Trước đây mọi cột thành lưới «nhãn trên / giá trị dưới» 2 cột → mỗi thẻ cao 4–6 dòng.
  Widget _buildCards(List<T> rows) {
    final cols = widget.columns.where((c) => !c.hideOnMobile).toList();
    final primary = cols.firstWhere((c) => c.primary, orElse: () => cols.first);
    final rest = cols.where((c) => !identical(c, primary)).toList();
    final numeric = rest.where((c) => c.numeric).toList();
    final lead = numeric.isNotEmpty ? numeric.first : null;
    final texts = rest.where((c) => !c.numeric && c.cell == null).toList();
    final widgetsCols = rest.where((c) => !c.numeric && c.cell != null).toList();
    final otherNums = numeric.skip(1).toList();
    bool blank(String v) => v.trim().isEmpty || v.trim() == '—' || v.trim() == '-';

    return Column(children: [
      for (final r in rows)
        InkWell(
          onTap: widget.onRowTap == null ? null : () => widget.onRowTap!(r),
          child: Container(
            padding: const EdgeInsets.fromLTRB(SboxSpace.md, 10, SboxSpace.md, 10),
            decoration: BoxDecoration(
              color: r == widget.selectedRow ? SboxColors.brand50 : SboxColors.surface,
              border: const Border(bottom: BorderSide(color: SboxColors.divider)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: primary.cell != null
                      ? primary.cell!(r)
                      : Text(primary.text!(r), style: SboxType.bodyStrong(), maxLines: 2, overflow: TextOverflow.ellipsis),
                ),
                if (lead != null) ...[
                  const SizedBox(width: SboxSpace.sm),
                  DefaultTextStyle.merge(
                    style: const TextStyle(fontWeight: FontWeight.w700),
                    child: lead.cell != null
                        ? lead.cell!(r)
                        : Text(lead.text!(r), maxLines: 1, style: SboxType.moneyStyle(size: SboxType.body)),
                  ),
                ],
                if (widget.rowActions != null) widget.rowActions!(r),
              ]),
              Builder(builder: (context) {
                final parts = [
                  for (final c in texts)
                    if (!blank(c.text!(r))) c.text!(r),
                ];
                if (parts.isEmpty) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(
                    parts.join(' · '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: SboxType.smallStyle(SboxColors.textSecondary),
                  ),
                );
              }),
              if (widgetsCols.isNotEmpty || otherNums.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Wrap(
                    spacing: SboxSpace.md,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      for (final c in widgetsCols) c.cell!(r),
                      for (final c in otherNums)
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          Text('${tr(c.label)} ', style: SboxType.captionStyle()),
                          c.cell != null
                              ? c.cell!(r)
                              : Text(c.text!(r),
                                  maxLines: 1,
                                  style: SboxType.moneyStyle(size: SboxType.small)),
                        ]),
                    ],
                  ),
                ),
            ]),
          ),
        ),
    ]);
  }
}

/// Thanh phân trang chuẩn: "1–20 / 245" · số dòng / trang · « ‹ 1 2 3 … › ».
class SboxPager extends StatelessWidget {
  const SboxPager({
    super.key,
    required this.page,
    required this.pageSize,
    required this.total,
    required this.onPage,
    this.onPageSize,
    this.pageSizes = const [20, 50, 100],
    this.extra = const [],
  });

  /// Nút phụ đặt cạnh dòng tổng (vd «Toàn màn hình»).
  final List<Widget> extra;
  final int page;
  final int pageSize;
  final int total;
  final ValueChanged<int> onPage;
  final ValueChanged<int>? onPageSize;
  final List<int> pageSizes;

  int get pages => math.max(1, (total / pageSize).ceil());

  @override
  Widget build(BuildContext context) {
    final mobile = SboxBreakpoints.isMobile(context);
    final from = total == 0 ? 0 : (page - 1) * pageSize + 1;
    final to = math.min(total, page * pageSize);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: SboxSpace.lg, vertical: SboxSpace.sm),
      decoration: const BoxDecoration(
        color: SboxColors.surface,
        border: Border(top: BorderSide(color: SboxColors.border)),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        runSpacing: SboxSpace.sm,
        spacing: SboxSpace.lg,
        children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            Text(tr('$from–$to / $total'), style: SboxType.smallStyle(SboxColors.textMuted)),
            if (onPageSize != null && !mobile) ...[
              const SizedBox(width: SboxSpace.lg),
              Text(tr('Hiển thị'), style: SboxType.smallStyle(SboxColors.textMuted)),
              const SizedBox(width: SboxSpace.xs),
              PopupMenuButton<int>(
                tooltip: tr('Số dòng mỗi trang'),
                onSelected: onPageSize,
                itemBuilder: (_) => [for (final s in pageSizes) PopupMenuItem(value: s, child: Text('$s'))],
                child: Container(
                  height: 28,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(border: Border.all(color: SboxColors.border), borderRadius: SboxRadius.smAll),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text('$pageSize', style: SboxType.smallStyle(SboxColors.text)),
                    const Icon(Icons.expand_more_rounded, size: 16, color: SboxColors.slate500),
                  ]),
                ),
              ),
            ],
            for (final w in extra) ...[const SizedBox(width: SboxSpace.md), w],
          ]),
          _SboxPagerButtons(page: page, pages: pages, onPage: onPage),
        ],
      ),
    );
  }
}

/// Thanh tìm kiếm + bộ lọc + nút, tự xuống dòng trên màn hẹp.
class SboxFilterBar extends StatelessWidget {
  const SboxFilterBar({
    super.key,
    this.searchHint = 'Tìm kiếm',
    this.onSearch,
    this.searchController,
    this.filters = const [],
    this.actions = const [],
  });

  final String searchHint;
  final ValueChanged<String>? onSearch;
  final TextEditingController? searchController;
  final List<Widget> filters;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final search = SizedBox(
      height: SboxSize.control,
      child: TextField(
        controller: searchController,
        onChanged: onSearch,
        style: SboxType.bodyStyle(),
        decoration: InputDecoration(
          hintText: tr(searchHint),
          prefixIcon: const Icon(Icons.search_rounded, size: 20),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
      ),
    );
    return LayoutBuilder(builder: (context, c) {
      final narrow = c.maxWidth < 720;
      if (narrow) {
        // Điện thoại: nút chính (một nút) đứng cạnh ô tìm; bộ lọc một hàng cuộn ngang
        // — không để bộ lọc xếp nhiều dòng đẩy danh sách xuống.
        final inline = actions.length == 1;
        final scrollItems = [...filters, if (!inline) ...actions];
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          inline ? Row(children: [Expanded(child: search), const SizedBox(width: SboxSpace.sm), actions.first]) : search,
          if (scrollItems.isNotEmpty) ...[
            const SizedBox(height: SboxSpace.sm),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                for (final w in scrollItems) ...[w, const SizedBox(width: SboxSpace.sm)],
              ]),
            ),
          ],
        ]);
      }
      return Row(children: [
        // Nhiều bộ lọc → ô tìm hẹp lại để cả hàng không phải xuống dòng.
        SizedBox(width: math.min(filters.length >= 4 ? 280 : 360, c.maxWidth * (filters.length >= 4 ? 0.26 : 0.4)), child: search),
        const SizedBox(width: SboxSpace.sm),
        Expanded(child: Wrap(spacing: SboxSpace.sm, runSpacing: SboxSpace.sm, children: filters)),
        if (actions.isNotEmpty) ...[
          const SizedBox(width: SboxSpace.sm),
          Wrap(spacing: SboxSpace.sm, children: actions),
        ],
      ]);
    });
  }
}

/// Ô lọc dạng nút có menu (Trạng thái: Tất cả ▾).
class SboxFilterChip<V> extends StatelessWidget {
  const SboxFilterChip({super.key, required this.label, required this.value, required this.options, required this.onChanged});

  final String label;
  final V value;
  /// value → nhãn hiển thị.
  final Map<V, String> options;
  final ValueChanged<V> onChanged;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<V>(
      tooltip: tr(label),
      onSelected: onChanged,
      itemBuilder: (_) => [
        for (final e in options.entries)
          PopupMenuItem(
            value: e.key,
            child: Row(children: [
              SizedBox(
                width: 22,
                child: e.key == value ? const Icon(Icons.check_rounded, size: 16, color: SboxColors.primary) : null,
              ),
              Text(tr(e.value)),
            ]),
          ),
      ],
      child: Container(
        height: SboxSize.control,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: SboxColors.surface,
          border: Border.all(color: SboxColors.borderStrong),
          borderRadius: SboxRadius.mdAll,
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text('${tr(label)}: ', style: SboxType.smallStyle(SboxColors.textMuted)),
          Text(tr(options[value] ?? ''), style: SboxType.smallStyle(SboxColors.text).copyWith(fontWeight: SboxType.semibold)),
          const SizedBox(width: 2),
          const Icon(Icons.expand_more_rounded, size: 18, color: SboxColors.slate500),
        ]),
      ),
    );
  }
}

/// Chỉ phần nút chuyển trang « ‹ 1 2 3 … › » — dùng khi màn đã có dòng tổng riêng.
class SboxPagerNav extends StatelessWidget {
  const SboxPagerNav({super.key, required this.page, required this.pages, required this.onPage});

  final int page;
  final int pages;
  final ValueChanged<int> onPage;

  @override
  Widget build(BuildContext context) {
    // Tái dùng phần nút của SboxPager (pageSize = 1 → mỗi trang 1 đơn vị).
    return _SboxPagerButtons(page: page, pages: math.max(1, pages), onPage: onPage);
  }
}

class _SboxPagerButtons extends StatelessWidget {
  const _SboxPagerButtons({required this.page, required this.pages, required this.onPage});

  final int page;
  final int pages;
  final ValueChanged<int> onPage;

  List<int?> _pageNumbers() {
    if (pages <= 7) return [for (var i = 1; i <= pages; i++) i];
    final set = <int>{1, pages, page - 1, page, page + 1}..removeWhere((p) => p < 1 || p > pages);
    final sorted = set.toList()..sort();
    final out = <int?>[];
    for (var i = 0; i < sorted.length; i++) {
      if (i > 0 && sorted[i] - sorted[i - 1] > 1) out.add(null);
      out.add(sorted[i]);
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final mobile = SboxBreakpoints.isMobile(context);
    Widget navBtn(IconData icon, String tip, int target, bool enabled) => Tooltip(
          message: tr(tip),
          child: InkWell(
            onTap: enabled ? () => onPage(target) : null,
            borderRadius: SboxRadius.smAll,
            child: SizedBox(
              width: 32,
              height: 32,
              child: Icon(icon, size: 18, color: enabled ? SboxColors.slate600 : SboxColors.slate300),
            ),
          ),
        );
    Widget num(int p) {
      final on = p == page;
      return InkWell(
        onTap: on ? null : () => onPage(p),
        borderRadius: SboxRadius.smAll,
        child: Container(
          constraints: const BoxConstraints(minWidth: 32),
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on ? SboxColors.primary : Colors.transparent,
            borderRadius: SboxRadius.smAll,
          ),
          child: Text('$p',
              style: TextStyle(
                fontSize: SboxType.small,
                fontWeight: on ? SboxType.semibold : SboxType.medium,
                color: on ? Colors.white : SboxColors.slate700,
              )),
        ),
      );
    }

    return Row(mainAxisSize: MainAxisSize.min, children: [
      navBtn(Icons.chevron_left_rounded, 'Trang trước', page - 1, page > 1),
      if (mobile)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(tr('Trang $page / $pages'), style: SboxType.smallStyle(SboxColors.text)),
        )
      else
        for (final p in _pageNumbers())
          p == null
              ? const SizedBox(width: 24, child: Center(child: Text('…', style: TextStyle(color: SboxColors.slate400))))
              : num(p),
      navBtn(Icons.chevron_right_rounded, 'Trang sau', page + 1, page < pages),
    ]);
  }
}
