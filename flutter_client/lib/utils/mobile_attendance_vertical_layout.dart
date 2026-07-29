import 'package:flutter/material.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

/// Mobile: nhân viên (hoặc chỉ 1 NV trong dữ liệu) → bảng dọc dễ đọc hơn bảng ngang.
bool preferMobileVerticalAttendanceView({
  required String? userRole,
  required int uniqueEmployeeCount,
}) {
  final role = (userRole ?? 'Employee').trim().toLowerCase();
  if (role == 'employee') return true;
  return uniqueEmployeeCount <= 1;
}

List<DateTime> attendanceDaysInRange(DateTimeRange range) {
  final dates = <DateTime>[];
  var cur = DateTime(range.start.year, range.start.month, range.start.day);
  final end = DateTime(range.end.year, range.end.month, range.end.day);
  while (!cur.isAfter(end)) {
    dates.add(cur);
    cur = cur.add(const Duration(days: 1));
  }
  return dates;
}

String attendanceVerticalDateShort(DateTime d) {
  final dd = d.day.toString().padLeft(2, '0');
  final mm = d.month.toString().padLeft(2, '0');
  return '$dd/$mm';
}

String attendanceVerticalWeekdayShort(DateTime d) {
  const days = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];
  return days[d.weekday - 1];
}

String attendanceVerticalDayTitle(DateTime d) {
  final dd = d.day.toString().padLeft(2, '0');
  final mm = d.month.toString().padLeft(2, '0');
  return '${attendanceVerticalWeekdayShort(d)}, $dd/$mm/${d.year}';
}

/// Một dòng bảng dọc: Ngày | Thứ | Chấm công | Tổng giờ | Đi đường | Tổng công
class MobileAttendanceVerticalRow {
  final String day;
  final String weekday;
  final Widget attendance;
  final String totalHours;
  final String travelHours;
  final String totalWork;
  final bool isToday;
  final VoidCallback? onTap;

  const MobileAttendanceVerticalRow({
    required this.day,
    required this.weekday,
    required this.attendance,
    required this.totalHours,
    this.travelHours = '—',
    required this.totalWork,
    this.isToday = false,
    this.onTap,
  });
}

/// Bảng dọc mobile với 5 cột cố định.
class MobileAttendanceVerticalTable extends StatelessWidget {
  static const headers = [
    'Ngày',
    'Thứ',
    'Chấm công',
    'Tổng giờ',
    'Đi đường',
    'Tổng công',
  ];

  final String? title;
  final List<MobileAttendanceVerticalRow> rows;
  final MobileAttendanceVerticalRow? totalRow;

  const MobileAttendanceVerticalTable({
    super.key,
    this.title,
    required this.rows,
    this.totalRow,
  });

  static const _headerBg = Color(0xFF1E3A5F);
  static const _border = Color(0xFFE4E4E7);
  static const _todayBg = Color(0xFFEFF6FF);
  static const _totalBg = Color(0xFFEFF6FF);
  static const _totalBorder = Color(0xFF93C5FD);

  static const _colFlex = [2, 2, 4, 2, 2, 2];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (title != null && title!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
              child: Row(
                children: [
                  const Icon(Icons.table_rows_outlined,
                      size: 18, color: _headerBg),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      tr(title!),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF18181B),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          _buildHeaderRow(),
          if (rows.isEmpty)
            Padding(
              padding: EdgeInsets.all(20),
              child: Center(
                child: Text(tr('Không có dữ liệu trong khoảng ngày đã chọn'),
                  style: TextStyle(fontSize: 12, color: Color(0xFF71717A)),
                ),
              ),
            )
          else ...[
            ...List.generate(rows.length, (i) => _buildDataRow(rows[i], i)),
            if (totalRow != null) _buildTotalRow(totalRow!),
          ],
        ],
      ),
    );
  }

  Widget _buildHeaderRow() {
    return Container(
      color: _headerBg,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: List.generate(headers.length, (i) {
          return Expanded(
            flex: _colFlex[i],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                tr(headers[i]),
                textAlign: i >= 2 ? TextAlign.center : TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildDataRow(MobileAttendanceVerticalRow row, int index) {
    final bg = row.isToday
        ? _todayBg
        : (index.isEven ? const Color(0xFFF9FAFB) : Colors.white);
    final cells = [
      row.day,
      row.weekday,
      null,
      row.totalHours,
      row.travelHours,
      row.totalWork,
    ];

    Widget rowBody = Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        border: Border(
          bottom: BorderSide(
            color: _border.withValues(alpha: 0.8),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: List.generate(cells.length, (i) {
          return Expanded(
            flex: _colFlex[i],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: i == 2
                  ? row.attendance
                  : Text(
                      tr(cells[i] ?? '—'),
                      textAlign: TextAlign.center,
                      maxLines: i == 2 ? 4 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight:
                            row.isToday ? FontWeight.w700 : FontWeight.w500,
                        color: i == 3 && cells[i] != '—'
                            ? const Color(0xFF16A34A)
                            : i == 4 && cells[i] != '—'
                                ? const Color(0xFFEA580C)
                                : i == 5 && cells[i] != '—'
                                    ? const Color(0xFF2563EB)
                                    : const Color(0xFF18181B),
                        height: 1.2,
                      ),
                    ),
            ),
          );
        }),
      ),
    );

    if (row.onTap != null) {
      return Material(
        color: Colors.transparent,
        child: InkWell(onTap: row.onTap, child: rowBody),
      );
    }
    return rowBody;
  }

  Widget _buildTotalRow(MobileAttendanceVerticalRow row) {
    final cells = [
      row.day,
      row.weekday,
      null,
      row.totalHours,
      row.travelHours,
      row.totalWork,
    ];

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: const BoxDecoration(
        color: _totalBg,
        border: Border(
          top: BorderSide(color: _totalBorder, width: 1),
          bottom: BorderSide(color: _totalBorder, width: 0.5),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: List.generate(cells.length, (i) {
          return Expanded(
            flex: _colFlex[i],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: i == 2
                  ? row.attendance
                  : Text(
                      tr(cells[i] ?? '—'),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: i == 3 && cells[i] != '—'
                            ? const Color(0xFF15803D)
                            : i == 4 && cells[i] != '—'
                                ? const Color(0xFFEA580C)
                                : i == 5 && cells[i] != '—'
                                    ? const Color(0xFF1D4ED8)
                                    : const Color(0xFF1E40AF),
                        height: 1.2,
                      ),
                    ),
            ),
          );
        }),
      ),
    );
  }
}

/// Nhãn chấm công dạng text (nhiều ca xuống dòng).
Widget mobileAttendancePunchText(String text) {
  return Center(
    child: Text(
      tr(text),
      textAlign: TextAlign.center,
      maxLines: 4,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        fontSize: 9,
        fontWeight: FontWeight.w600,
        color: Color(0xFF18181B),
        height: 1.25,
      ),
    ),
  );
}

/// Một dòng bảng dọc theo ca (8 cột, cuộn ngang).
class MobileAttendanceShiftVerticalRow {
  final String day;
  final String weekday;
  final Widget attendance;
  final String totalWork;
  final String totalHours;
  final String travelHours;
  final String late;
  final String early;
  final String overtime;
  final bool isToday;
  final VoidCallback? onTap;

  const MobileAttendanceShiftVerticalRow({
    required this.day,
    required this.weekday,
    required this.attendance,
    required this.totalWork,
    required this.totalHours,
    this.travelHours = '—',
    required this.late,
    required this.early,
    required this.overtime,
    this.isToday = false,
    this.onTap,
  });
}

/// Bảng dọc tổng hợp theo ca — cuộn ngang khi nhiều cột.
class MobileAttendanceShiftVerticalTable extends StatelessWidget {
  static const headers = [
    'Ngày',
    'Thứ',
    'Chấm công',
    'Tổng công',
    'Tổng giờ',
    'Đi đường',
    'Đi trễ',
    'Về sớm',
    'Tăng ca',
  ];

  static const _colWidths = [
    54.0,
    42.0,
    96.0,
    58.0,
    58.0,
    54.0,
    54.0,
    54.0,
    54.0,
  ];

  final String? title;
  final List<MobileAttendanceShiftVerticalRow> rows;
  final MobileAttendanceShiftVerticalRow? totalRow;

  const MobileAttendanceShiftVerticalTable({
    super.key,
    this.title,
    required this.rows,
    this.totalRow,
  });

  static const _headerBg = Color(0xFF1E3A5F);
  static const _border = Color(0xFFE4E4E7);
  static const _todayBg = Color(0xFFEFF6FF);
  static const _totalBg = Color(0xFFEFF6FF);
  static const _totalBorder = Color(0xFF93C5FD);

  double get _tableWidth =>
      _colWidths.fold<double>(0, (sum, w) => sum + w);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (title != null && title!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.table_rows_outlined,
                          size: 18, color: _headerBg),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          tr(title!),
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF18181B),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(tr('Vuốt ngang để xem đủ cột'),
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: _tableWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeaderRow(),
                  if (rows.isEmpty)
                    Padding(
                      padding: EdgeInsets.all(20),
                      child: Center(
                        child: Text(tr('Không có dữ liệu trong khoảng ngày đã chọn'),
                          style: TextStyle(
                              fontSize: 12, color: Color(0xFF71717A)),
                        ),
                      ),
                    )
                  else ...[
                    ...List.generate(
                        rows.length, (i) => _buildDataRow(rows[i], i)),
                    if (totalRow != null) _buildTotalRow(totalRow!),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderRow() {
    return Container(
      color: _headerBg,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: List.generate(headers.length, (i) {
          return SizedBox(
            width: _colWidths[i],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                tr(headers[i]),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  height: 1.15,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildDataRow(MobileAttendanceShiftVerticalRow row, int index) {
    final bg = row.isToday
        ? _todayBg
        : (index.isEven ? const Color(0xFFF9FAFB) : Colors.white);
    final textCells = [
      row.day,
      row.weekday,
      row.totalWork,
      row.totalHours,
      row.travelHours,
      row.late,
      row.early,
      row.overtime,
    ];

    Widget rowBody = Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        border: Border(
          bottom: BorderSide(
            color: _border.withValues(alpha: 0.8),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: _colWidths[0],
            child: _textCell(textCells[0], row.isToday),
          ),
          SizedBox(
            width: _colWidths[1],
            child: _textCell(textCells[1], row.isToday),
          ),
          SizedBox(
            width: _colWidths[2],
            child: row.attendance,
          ),
          for (var i = 3; i < 9; i++)
            SizedBox(
              width: _colWidths[i],
              child: _textCell(
                textCells[i - 1],
                row.isToday,
                color: _cellColor(i - 1, textCells[i - 1]),
              ),
            ),
        ],
      ),
    );

    if (row.onTap != null) {
      return Material(
        color: Colors.transparent,
        child: InkWell(onTap: row.onTap, child: rowBody),
      );
    }
    return rowBody;
  }

  Widget _buildTotalRow(MobileAttendanceShiftVerticalRow row) {
    final textCells = [
      row.day,
      row.weekday,
      row.totalWork,
      row.totalHours,
      row.travelHours,
      row.late,
      row.early,
      row.overtime,
    ];

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: const BoxDecoration(
        color: _totalBg,
        border: Border(
          top: BorderSide(color: _totalBorder, width: 1),
          bottom: BorderSide(color: _totalBorder, width: 0.5),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: _colWidths[0],
            child: _textCell(textCells[0], false, bold: true),
          ),
          SizedBox(
            width: _colWidths[1],
            child: _textCell(textCells[1], false, bold: true),
          ),
          SizedBox(
            width: _colWidths[2],
            child: row.attendance,
          ),
          for (var i = 3; i < 9; i++)
            SizedBox(
              width: _colWidths[i],
              child: _textCell(
                textCells[i - 1],
                false,
                bold: true,
                color: _cellColor(i - 1, textCells[i - 1]) ??
                    const Color(0xFF1E40AF),
              ),
            ),
        ],
      ),
    );
  }

  Widget _textCell(String text, bool isToday,
      {Color? color, bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        tr(text),
        textAlign: TextAlign.center,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 10,
          fontWeight: bold || isToday ? FontWeight.w800 : FontWeight.w500,
          color: color ?? const Color(0xFF18181B),
          height: 1.2,
        ),
      ),
    );
  }

  Color? _cellColor(int colIndex, String value) {
    if (value == '—') return null;
    switch (colIndex) {
      case 2:
        return const Color(0xFF2563EB);
      case 3:
        return const Color(0xFF16A34A);
      case 4:
        return const Color(0xFFEA580C);
      case 5:
        return const Color(0xFFF59E0B);
      case 6:
        return const Color(0xFFEF4444);
      case 7:
        return const Color(0xFF8B5CF6);
      default:
        return null;
    }
  }
}

/// Một dòng bảng dọc lương (cột đầu = nhân viên).
class MobilePayrollVerticalRow {
  final String employeeName;
  final String employeeSubtitle;
  final List<String> cells;
  final List<Color?>? cellColors;
  final VoidCallback? onTap;

  const MobilePayrollVerticalRow({
    required this.employeeName,
    required this.employeeSubtitle,
    required this.cells,
    this.cellColors,
    this.onTap,
  });
}

/// Bảng dọc tổng hợp lương — cột NV cố định, các cột còn lại cuộn ngang.
class MobilePayrollVerticalTable extends StatelessWidget {
  final String? title;
  final List<String> headers;
  final List<double> columnWidths;
  final List<MobilePayrollVerticalRow> rows;
  final MobilePayrollVerticalRow? totalRow;

  const MobilePayrollVerticalTable({
    super.key,
    this.title,
    required this.headers,
    required this.columnWidths,
    required this.rows,
    this.totalRow,
  });

  static const _headerBg = Color(0xFF1E3A5F);
  static const _border = Color(0xFFE4E4E7);
  static const _totalBg = Color(0xFFEFF6FF);
  static const _totalFrozenBg = Color(0xFFDBEAFE);
  static const _totalBorder = Color(0xFF93C5FD);
  static const _empColW = 118.0;
  static const _rowH = 46.0;
  static const _hdrH = 44.0;

  double get _scrollWidth =>
      columnWidths.fold<double>(0, (sum, w) => sum + w);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (title != null && title!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.table_rows_outlined,
                          size: 18, color: _headerBg),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          tr(title!),
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF18181B),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(tr('Vuốt ngang để xem đủ cột'),
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
          if (rows.isEmpty)
            Padding(
              padding: EdgeInsets.all(20),
              child: Center(
                child: Text(tr('Không có dữ liệu lương'),
                  style: TextStyle(fontSize: 12, color: Color(0xFF71717A)),
                ),
              ),
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildFrozenEmployeeColumn(),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: _scrollWidth > 0 ? _scrollWidth : 1,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildScrollableHeader(),
                          ...List.generate(
                            rows.length,
                            (i) => _buildScrollableRow(rows[i], i),
                          ),
                          if (totalRow != null)
                            _buildScrollableRow(totalRow!, -1, isTotal: true),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildFrozenEmployeeColumn() {
    return SizedBox(
      width: _empColW,
      child: Column(
        children: [
          Container(
            height: _hdrH,
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: const BoxDecoration(
              color: _headerBg,
              border: Border(
                right: BorderSide(color: Colors.white24),
                bottom: BorderSide(color: Colors.white24, width: 0.5),
              ),
            ),
            child: Text(tr('Nhân viên'),
              style: TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          ...List.generate(rows.length, (i) {
            final row = rows[i];
            return _buildFrozenEmployeeCell(row, i.isEven);
          }),
          if (totalRow != null) _buildFrozenEmployeeCell(totalRow!, true, isTotal: true),
        ],
      ),
    );
  }

  Widget _buildFrozenEmployeeCell(
    MobilePayrollVerticalRow row,
    bool isEven, {
    bool isTotal = false,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isTotal ? null : row.onTap,
        child: Container(
          height: _rowH,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: isTotal
                ? _totalFrozenBg
                : (isEven ? const Color(0xFFF4F4F5) : Colors.white),
            border: Border(
              top: isTotal
                  ? const BorderSide(color: _totalBorder, width: 1)
                  : BorderSide.none,
              right: const BorderSide(color: Color(0xFFD4D4D8)),
              bottom: BorderSide(
                color: isTotal ? _totalBorder : const Color(0xFFE4E4E7),
                width: 0.5,
              ),
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr(row.employeeName),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: isTotal ? FontWeight.w800 : FontWeight.w600,
                  color: isTotal
                      ? const Color(0xFF1E40AF)
                      : const Color(0xFF18181B),
                ),
              ),
              if (row.employeeSubtitle.isNotEmpty)
                Text(
                  tr(row.employeeSubtitle),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 9,
                    color: isTotal
                        ? const Color(0xFF1D4ED8)
                        : const Color(0xFF71717A),
                    fontWeight:
                        isTotal ? FontWeight.w700 : FontWeight.normal,
                  ),
                ),
              if (!isTotal)
                Text(tr('Chạm xem'),
                  style: TextStyle(fontSize: 8, color: Color(0xFF2563EB)),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildScrollableHeader() {
    return Container(
      height: _hdrH,
      color: _headerBg,
      child: Row(
        children: List.generate(headers.length, (i) {
          return SizedBox(
            width: columnWidths[i],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Center(
                child: Text(
                  tr(headers[i]),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    height: 1.15,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildScrollableRow(
    MobilePayrollVerticalRow row,
    int index, {
    bool isTotal = false,
  }) {
    final isEven = index < 0 ? true : index.isEven;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isTotal ? null : row.onTap,
        child: Container(
          height: _rowH,
          color: isTotal
              ? _totalBg
              : (isEven ? const Color(0xFFF9FAFB) : Colors.white),
          child: Row(
            children: List.generate(headers.length, (i) {
              final value = i < row.cells.length ? row.cells[i] : '—';
              final color = row.cellColors != null && i < row.cellColors!.length
                  ? row.cellColors![i]
                  : null;
              return SizedBox(
                width: columnWidths[i],
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    border: Border(
                      top: isTotal
                          ? const BorderSide(color: _totalBorder, width: 1)
                          : BorderSide.none,
                      right: const BorderSide(color: Color(0xFFE4E4E7), width: 0.5),
                      bottom: BorderSide(
                        color: isTotal ? _totalBorder : const Color(0xFFE4E4E7),
                        width: 0.5,
                      ),
                    ),
                  ),
                  child: Text(
                    tr(value),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: isTotal ||
                              headers[i].contains('THỰC NHẬN') ||
                              headers[i].contains('Thực nhận')
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: color ??
                          (isTotal
                              ? const Color(0xFF1E40AF)
                              : const Color(0xFF18181B)),
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

/// Nhãn vắng/phép/lễ trong cột Chấm công.
Widget mobileAttendanceAbsenceLabel(
  String label, {
  Color color = const Color(0xFFEF4444),
  VoidCallback? onTap,
}) {
  final child = Text(
    tr(label),
    textAlign: TextAlign.center,
    style: TextStyle(
      fontSize: 10,
      fontWeight: FontWeight.w600,
      color: color,
    ),
  );
  if (onTap == null) {
    return Center(child: child);
  }
  return GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: Center(child: child),
  );
}
