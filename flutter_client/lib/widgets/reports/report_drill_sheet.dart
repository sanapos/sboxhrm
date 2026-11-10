import 'package:flutter/material.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

import '../../theme/sbox_tokens.dart';
import '../attendance/attendance_employee_list.dart';

/// Một dòng trong danh sách chi tiết của một chip số liệu.
///
/// Chip «Nhân viên nghỉ 5» → 5 dòng, mỗi dòng một người; chip «Tổng tiền phạt»
/// → mỗi dòng một phiếu kèm số tiền. Tổng / số đếm của các dòng phải khớp số trên chip.
class ReportDrillRow {
  const ReportDrillRow({
    required this.title,
    this.subtitle,
    this.trailing,
    this.trailingColor,
    this.icon,
    this.onTap,
  });

  /// Tên người / mã đơn / tên hàng.
  final String title;

  /// Dòng phụ: ngày, chi nhánh, trạng thái, lý do…
  final String? subtitle;

  /// Số bên phải: «3 ngày», «150.000 đ», «92%».
  final String? trailing;
  final Color? trailingColor;

  /// Bỏ trống → ô chữ cái đầu của [title] (hợp với danh sách người).
  final IconData? icon;

  /// Bấm dòng → mở chi tiết gốc (đơn, hồ sơ nhân viên…). Sheet tự đóng trước khi gọi.
  final VoidCallback? onTap;
}

/// Sheet «số này từ đâu ra»: liệt kê đúng các dòng đã dùng để tính chip.
///
/// - [rows]: dữ liệu đã có trên màn (lọc tại chỗ).
/// - [load]: tải từ API khi mở (chip chỉ có số tổng); hiện vòng quay / lỗi + thử lại.
/// - [note]: cách tính (chip tỷ lệ, trung bình) hoặc ghi chú phạm vi (kỳ, chi nhánh).
/// - [total]: dòng tổng ở cuối (vd «Tổng 1.250.000 đ») để đối chiếu với chip.
/// - [countLabel]: thay số đếm trong tiêu đề (mặc định là số dòng).
Future<void> showReportDrillSheet(
  BuildContext context, {
  required String title,
  String? subtitle,
  String? note,
  List<ReportDrillRow>? rows,
  Future<List<ReportDrillRow>> Function()? load,
  String? total,
  String? countLabel,
  bool showCount = true,
  String emptyText = 'Không có dữ liệu',
  String? footer,
}) {
  assert(rows != null || load != null, 'Cần rows hoặc load');
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => _DrillSheet(
      title: title,
      subtitle: subtitle,
      note: note,
      rows: rows,
      load: load,
      total: total,
      countLabel: countLabel,
      showCount: showCount,
      emptyText: emptyText,
      footer: footer,
    ),
  );
}

class _DrillSheet extends StatefulWidget {
  const _DrillSheet({
    required this.title,
    required this.subtitle,
    required this.note,
    required this.rows,
    required this.load,
    required this.total,
    required this.countLabel,
    required this.showCount,
    required this.emptyText,
    required this.footer,
  });

  final String title;
  final String? subtitle;
  final String? note;
  final List<ReportDrillRow>? rows;
  final Future<List<ReportDrillRow>> Function()? load;
  final String? total;
  final String? countLabel;
  final bool showCount;
  final String emptyText;
  final String? footer;

  @override
  State<_DrillSheet> createState() => _DrillSheetState();
}

class _DrillSheetState extends State<_DrillSheet> {
  String _q = '';
  List<ReportDrillRow>? _rows;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _rows = widget.rows;
    if (_rows == null) _fetch();
  }

  Future<void> _fetch() async {
    setState(() {
      _rows = null;
      _error = null;
    });
    try {
      final r = await widget.load!();
      if (mounted) setState(() => _rows = r);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final all = _rows ?? const <ReportDrillRow>[];
    final q = attendanceFoldVi(_q.trim());
    final rows = q.isEmpty
        ? all
        : all.where((r) => attendanceFoldVi('${r.title} ${r.subtitle ?? ''} ${r.trailing ?? ''}').contains(q)).toList();
    final count = widget.countLabel ?? (_rows == null ? null : '${all.length}');
    final head = widget.showCount && count != null ? '${tr(widget.title)} ($count)' : tr(widget.title);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: all.length > 6 || _rows == null ? 0.75 : 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.95,
      builder: (context, controller) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 8, bottom: 4),
              width: 36,
              height: 4,
              decoration: BoxDecoration(color: SboxColors.slate300, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 8, 4),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(head, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: SboxColors.slate900)),
                  if (widget.subtitle != null)
                    Text(tr(widget.subtitle!), style: const TextStyle(fontSize: 12, color: SboxColors.slate500)),
                ]),
              ),
              IconButton(
                tooltip: tr('Đóng'),
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ]),
          ),
          if (widget.note != null)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: SboxColors.slate50, borderRadius: BorderRadius.circular(10)),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.info_outline, size: 16, color: SboxColors.slate500),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(tr(widget.note!), style: const TextStyle(fontSize: 12.5, color: SboxColors.slate700, height: 1.35)),
                ),
              ]),
            ),
          if (all.length > 8)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                onChanged: (v) => setState(() => _q = v),
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: const Icon(Icons.search, size: 20),
                  hintText: tr('Tìm theo tên, mã…'),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          const Divider(height: 1),
          Expanded(child: _body(controller, all, rows)),
          if (widget.total != null && _rows != null && all.isNotEmpty)
            Container(
              color: SboxColors.slate50,
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: Text(tr(widget.total!),
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: SboxColors.slate900)),
            ),
          if (widget.footer != null && _rows != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
              child: Text(tr(widget.footer!), style: const TextStyle(fontSize: 12, color: SboxColors.slate500)),
            ),
        ],
      ),
    );
  }

  Widget _body(ScrollController controller, List<ReportDrillRow> all, List<ReportDrillRow> rows) {
    if (_error != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(tr('Không tải được dữ liệu'), style: const TextStyle(color: SboxColors.slate600)),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: _fetch, child: Text(tr('Thử lại'))),
        ]),
      );
    }
    if (_rows == null) return const Center(child: CircularProgressIndicator());
    if (rows.isEmpty) {
      return Center(
        child: Text(tr(all.isEmpty ? widget.emptyText : 'Không tìm thấy'), style: const TextStyle(color: SboxColors.slate500)),
      );
    }
    return ListView.separated(
      controller: controller,
      itemCount: rows.length,
      separatorBuilder: (_, __) => const Divider(height: 1, indent: 64),
      itemBuilder: (context, i) => _row(context, rows[i]),
    );
  }

  Widget _row(BuildContext context, ReportDrillRow r) {
    return ListTile(
      dense: true,
      onTap: r.onTap == null
          ? null
          : () {
              Navigator.of(context).pop();
              r.onTap!();
            },
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: SboxColors.brand50,
        child: r.icon != null
            ? Icon(r.icon, size: 18, color: SboxColors.brand800)
            : Text(attendanceInitials(r.title),
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: SboxColors.brand800)),
      ),
      title: Text(tr(r.title), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
      subtitle: r.subtitle == null || r.subtitle!.isEmpty ? null : Text(tr(r.subtitle!), maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: r.trailing == null
          ? (r.onTap != null ? const Icon(Icons.chevron_right, color: SboxColors.slate400) : null)
          : Text(tr(r.trailing!),
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: r.trailingColor ?? SboxColors.slate800)),
    );
  }
}
