import 'package:flutter/material.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

import '../../theme/sbox_tokens.dart';
import 'attendance_employee_list.dart';

/// Một dòng trong danh sách người (chạm ô số liệu → xem những ai).
class AttendancePersonRow {
  const AttendancePersonRow({
    required this.name,
    this.subtitle,
    this.trailing,
    this.trailingColor,
    this.onTap,
  });

  final String name;

  /// Dòng phụ: mã NV, chi nhánh, giờ vào–ra, các ngày đi trễ…
  final String? subtitle;

  /// Số bên phải: «22 công», «12 phút», «48,5 giờ».
  final String? trailing;
  final Color? trailingColor;
  final VoidCallback? onTap;
}

/// Danh sách người cho một ô số liệu (Nhân viên, Đi trễ, Vắng…) — dạng sheet kéo được,
/// có ô tìm khi danh sách dài. Dùng chung cho Tổng hợp chấm công, Theo ca và SBOX BOSS.
Future<void> showAttendancePeopleSheet(
  BuildContext context, {
  required String title,
  String? subtitle,
  required List<AttendancePersonRow> rows,
  String emptyText = 'Không có nhân viên nào',
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => _PeopleSheet(
      title: title,
      subtitle: subtitle,
      rows: rows,
      emptyText: emptyText,
    ),
  );
}

class _PeopleSheet extends StatefulWidget {
  const _PeopleSheet({
    required this.title,
    required this.subtitle,
    required this.rows,
    required this.emptyText,
  });

  final String title;
  final String? subtitle;
  final List<AttendancePersonRow> rows;
  final String emptyText;

  @override
  State<_PeopleSheet> createState() => _PeopleSheetState();
}

class _PeopleSheetState extends State<_PeopleSheet> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final q = attendanceFoldVi(_q.trim());
    final rows = q.isEmpty
        ? widget.rows
        : widget.rows
            .where((r) => attendanceFoldVi('${r.name} ${r.subtitle ?? ''}').contains(q))
            .toList();
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: widget.rows.length > 6 ? 0.75 : 0.5,
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
              decoration: BoxDecoration(
                color: SboxColors.slate300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 8, 4),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    tr('${widget.title} (${widget.rows.length})'),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: SboxColors.slate900),
                  ),
                  if (widget.subtitle != null)
                    Text(tr(widget.subtitle!),
                        style: const TextStyle(fontSize: 12, color: SboxColors.slate500)),
                ]),
              ),
              IconButton(
                tooltip: tr('Đóng'),
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ]),
          ),
          if (widget.rows.length > 8)
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
          Expanded(
            child: rows.isEmpty
                ? Center(
                    child: Text(tr(widget.rows.isEmpty ? widget.emptyText : 'Không tìm thấy'),
                        style: const TextStyle(color: SboxColors.slate500)),
                  )
                : ListView.separated(
                    controller: controller,
                    itemCount: rows.length,
                    separatorBuilder: (_, __) => const Divider(height: 1, indent: 64),
                    itemBuilder: (context, i) => _row(context, rows[i]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, AttendancePersonRow r) {
    final initials = attendanceInitials(r.name);
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
        child: Text(initials,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: SboxColors.brand800)),
      ),
      title: Text(tr(r.name),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
      subtitle: r.subtitle == null || r.subtitle!.isEmpty
          ? null
          : Text(tr(r.subtitle!), maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: r.trailing == null
          ? (r.onTap != null ? const Icon(Icons.chevron_right, color: SboxColors.slate400) : null)
          : Text(tr(r.trailing!),
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700, color: r.trailingColor ?? SboxColors.slate800)),
    );
  }
}
