import 'package:flutter/material.dart';

import '../hrm_collapsible_overview.dart';

/// Khối bộ lọc nhiều dòng của báo cáo: mở màn là thu gọn còn 1 dòng «Bộ lọc · [summary]», bấm để mở.
/// Trạng thái thu / mở nhớ theo [storageKey] trong phiên (mặc định thu gọn).
class ReportFilterCollapse extends StatefulWidget {
  const ReportFilterCollapse({
    super.key,
    required this.child,
    this.summary,
    this.storageKey,
    this.title = 'Bộ lọc',
  });

  /// Bộ lọc đầy đủ (ô tìm, chip, ngày…).
  final Widget child;

  /// Tóm tắt bộ lọc đang chọn — hiện khi thu gọn (vd «Khách hàng · gồm dư 0 · tìm "An"»).
  final String? summary;
  final String? storageKey;
  final String title;

  static final Map<String, bool> _open = {};

  @override
  State<ReportFilterCollapse> createState() => _ReportFilterCollapseState();
}

class _ReportFilterCollapseState extends State<ReportFilterCollapse> {
  late bool _open = ReportFilterCollapse._open[widget.storageKey ?? ''] ?? false;

  void _toggle() {
    setState(() => _open = !_open);
    if (widget.storageKey != null) ReportFilterCollapse._open[widget.storageKey!] = _open;
  }

  @override
  Widget build(BuildContext context) {
    return HrmCollapsibleOverview(
      key: const ValueKey('report-filter-collapse'),
      title: widget.title,
      subtitle: widget.summary,
      expanded: _open,
      onToggle: _toggle,
      child: widget.child,
    );
  }
}
