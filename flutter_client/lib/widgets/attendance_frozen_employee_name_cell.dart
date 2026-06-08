import 'package:flutter/material.dart';

/// Chiều rộng cột tên NV cố định (bảng chấm công ngang).
double attendanceFrozenEmployeeColWidth(BuildContext context) =>
    (MediaQuery.sizeOf(context).width * 0.44).clamp(152.0, 200.0);

/// Nhãn tên NV trong ô cột cố định: luôn 1 dòng, phụ đề tách riêng.
class AttendanceFrozenEmployeeNameCell extends StatelessWidget {
  const AttendanceFrozenEmployeeNameCell({
    super.key,
    required this.name,
    this.subtext,
    this.subtextColor = const Color(0xFF16A34A),
    this.code,
    this.showCode = false,
  });

  final String name;
  final String? subtext;
  final Color subtextColor;
  final String? code;
  final bool showCode;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: name,
          waitDuration: const Duration(milliseconds: 350),
          child: Text(
            name,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: Color(0xFF18181B),
              height: 1.2,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (showCode && code != null && code!.isNotEmpty) ...[
          const SizedBox(height: 1),
          Text(
            code!,
            style: const TextStyle(fontSize: 9, color: Color(0xFF71717A)),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
        if (subtext != null && subtext!.isNotEmpty) ...[
          const SizedBox(height: 1),
          Text(
            subtext!,
            style: TextStyle(
              fontSize: 9,
              color: subtextColor,
              fontWeight: FontWeight.bold,
              height: 1.1,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }
}
