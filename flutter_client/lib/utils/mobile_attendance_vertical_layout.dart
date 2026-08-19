import 'package:flutter/material.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

import '../widgets/pos/pos_theme.dart';
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

/// Một dòng bảng dọc: Ngày | Thứ | Chấm công | Giờ ca… | Tổng giờ | [Đi đường] | Tổng công
class MobileAttendanceVerticalRow {
  final String day;
  final String weekday;
  final Widget attendance;
  final List<String> shiftHours;
  final String totalHours;
  final String travelHours;
  final String totalWork;
  final bool isToday;
  final VoidCallback? onTap;

  const MobileAttendanceVerticalRow({
    required this.day,
    required this.weekday,
    required this.attendance,
    this.shiftHours = const [],
    required this.totalHours,
    this.travelHours = '—',
    required this.totalWork,
    this.isToday = false,
    this.onTap,
  });
}

/// Bảng dọc mobile — cuộn ngang khi có cột giờ từng ca.
class MobileAttendanceVerticalTable extends StatelessWidget {
  final String? title;
  final List<MobileAttendanceVerticalRow> rows;
  final MobileAttendanceVerticalRow? totalRow;
  final int maxShifts;
  final bool showTravel;

  const MobileAttendanceVerticalTable({
    super.key,
    this.title,
    required this.rows,
    this.totalRow,
    this.maxShifts = 0,
    this.showTravel = true,
  });

  static const _headerBg = Color(0xFFF4F6F8);
  static const _accent = PosTheme.kiotBlue;
  static const _border = Color(0xFFE4E4E7);
  static const _todayBg = Color(0xFFEFF6FF);
  static const _totalBg = Color(0xFFEFF6FF);
  static const _totalBorder = Color(0xFF93C5FD);

  List<String> get _headers {
    final h = <String>['Ngày', 'Thứ', 'Chấm công'];
    for (var i = 1; i <= maxShifts; i++) {
      h.add('Giờ ca $i');
    }
    h.add('Tổng giờ');
    if (showTravel) h.add('Đi đường');
    h.add('Tổng công');
    return h;
  }

  List<double> get _colWidths {
    final w = <double>[54, 42, 96];
    for (var i = 0; i < maxShifts; i++) {
      w.add(56);
    }
    w.add(58);
    if (showTravel) w.add(54);
    w.add(52);
    return w;
  }

  double get _tableWidth => _colWidths.fold<double>(0, (s, w) => s + w);

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
              child: Row(
                children: [
                  const Icon(Icons.table_rows_outlined,
                      size: 18, color: _accent),
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
          if (maxShifts > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
              child: Text(
                tr('Vuốt ngang để xem giờ từng ca'),
                style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
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
                      padding: const EdgeInsets.all(20),
                      child: Center(
                        child: Text(
                          tr('Không có dữ liệu trong khoảng ngày đã chọn'),
                          style: const TextStyle(
                              fontSize: 12, color: Color(0xFF71717A)),
                        ),
                      ),
                    )
                  else ...[
                    ...List.generate(rows.length, (i) => _buildDataRow(rows[i], i)),
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
    final headers = _headers;
    final widths = _colWidths;
    return Container(
      color: _headerBg,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: List.generate(headers.length, (i) {
          return SizedBox(
            width: widths[i],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                tr(headers[i]),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF374151),
                  fontSize: 10,
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

  List<String?> _textCells(MobileAttendanceVerticalRow row) {
    final cells = <String?>[row.day, row.weekday];
    for (var i = 0; i < maxShifts; i++) {
      cells.add(i < row.shiftHours.length ? row.shiftHours[i] : '—');
    }
    cells.add(row.totalHours);
    if (showTravel) cells.add(row.travelHours);
    cells.add(row.totalWork);
    return cells;
  }

  Color _cellColor(int textIndex, String? value, {required bool total}) {
    if (value == null || value == '—') {
      return total ? const Color(0xFF1E40AF) : const Color(0xFF18181B);
    }
    final shiftEnd = maxShifts;
    if (textIndex >= 0 && textIndex < shiftEnd) {
      return const Color(0xFF0F766E);
    }
    if (textIndex == shiftEnd) {
      return total ? const Color(0xFF15803D) : const Color(0xFF16A34A);
    }
    var idx = shiftEnd + 1;
    if (showTravel) {
      if (textIndex == idx) return const Color(0xFFEA580C);
      idx++;
    }
    if (textIndex == idx) {
      return total ? const Color(0xFF1D4ED8) : const Color(0xFF2563EB);
    }
    return total ? const Color(0xFF1E40AF) : const Color(0xFF18181B);
  }

  Widget _buildDataRow(MobileAttendanceVerticalRow row, int index) {
    final bg = row.isToday
        ? _todayBg
        : (index.isEven ? const Color(0xFFF9FAFB) : Colors.white);
    final texts = _textCells(row);
    final widths = _colWidths;
    Widget rowBody = Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        border: Border(
          bottom: BorderSide(color: _border.withValues(alpha: 0.8), width: 0.5),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: widths[0],
            child: _plainCell(texts[0], row.isToday),
          ),
          SizedBox(
            width: widths[1],
            child: _plainCell(texts[1], row.isToday),
          ),
          SizedBox(width: widths[2], child: row.attendance),
          for (var i = 3; i < widths.length; i++)
            SizedBox(
              width: widths[i],
              child: _plainCell(
                texts[i - 1],
                row.isToday,
                color: _cellColor(i - 3, texts[i - 1], total: false),
                bold: row.isToday,
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

  Widget _buildTotalRow(MobileAttendanceVerticalRow row) {
    final texts = _textCells(row);
    final widths = _colWidths;
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
            width: widths[0],
            child: _plainCell(texts[0], true, color: const Color(0xFF1E40AF)),
          ),
          SizedBox(
            width: widths[1],
            child: _plainCell(texts[1], true, color: const Color(0xFF1E40AF)),
          ),
          SizedBox(width: widths[2], child: row.attendance),
          for (var i = 3; i < widths.length; i++)
            SizedBox(
              width: widths[i],
              child: _plainCell(
                texts[i - 1],
                true,
                color: _cellColor(i - 3, texts[i - 1], total: true),
                bold: true,
              ),
            ),
        ],
      ),
    );
  }

  Widget _plainCell(String? text, bool emphasize,
      {Color? color, bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        tr(text ?? '—'),
        textAlign: TextAlign.center,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 10,
          fontWeight: (emphasize || bold) ? FontWeight.w800 : FontWeight.w500,
          color: color ?? const Color(0xFF18181B),
          height: 1.2,
        ),
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

/// Một dòng bảng dọc theo ca — cột giờ từng ca + ẩn đi đường khi tắt.
class MobileAttendanceShiftVerticalRow {
  final String day;
  final String weekday;
  final Widget attendance;
  final List<String> shiftHours;
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
    this.shiftHours = const [],
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

/// Bảng dọc tổng hợp theo ca — cuộn ngang khi có cột giờ từng ca.
class MobileAttendanceShiftVerticalTable extends StatelessWidget {
  final String? title;
  final List<MobileAttendanceShiftVerticalRow> rows;
  final MobileAttendanceShiftVerticalRow? totalRow;
  final List<String> shiftHourLabels;
  final bool showTravel;

  const MobileAttendanceShiftVerticalTable({
    super.key,
    this.title,
    required this.rows,
    this.totalRow,
    this.shiftHourLabels = const [],
    this.showTravel = true,
  });

  static const _headerBg = Color(0xFFF4F6F8);
  static const _accent = PosTheme.kiotBlue;
  static const _border = Color(0xFFE4E4E7);
  static const _todayBg = Color(0xFFEFF6FF);
  static const _totalBg = Color(0xFFEFF6FF);
  static const _totalBorder = Color(0xFF93C5FD);

  List<String> get _headers {
    final h = <String>['Ngày', 'Thứ', 'Chấm công'];
    for (final name in shiftHourLabels) {
      h.add(name.startsWith('Giờ ') ? name : 'Giờ $name');
    }
    h.addAll(['Tổng công', 'Tổng giờ']);
    if (showTravel) h.add('Đi đường');
    h.addAll(['Đi trễ', 'Về sớm', 'Tăng ca']);
    return h;
  }

  List<double> get _colWidths {
    final w = <double>[54, 42, 96];
    for (var i = 0; i < shiftHourLabels.length; i++) {
      w.add(64);
    }
    w.addAll([58, 58]);
    if (showTravel) w.add(54);
    w.addAll([54, 54, 54]);
    return w;
  }

  double get _tableWidth => _colWidths.fold<double>(0, (sum, w) => sum + w);

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
                          size: 18, color: _accent),
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
                  Text(
                    tr(shiftHourLabels.isNotEmpty
                        ? 'Vuốt ngang để xem giờ từng ca'
                        : 'Vuốt ngang để xem đủ cột'),
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
                      padding: const EdgeInsets.all(20),
                      child: Center(
                        child: Text(
                          tr('Không có dữ liệu trong khoảng ngày đã chọn'),
                          style: const TextStyle(
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
    final headers = _headers;
    final widths = _colWidths;
    return Container(
      color: _headerBg,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: List.generate(headers.length, (i) {
          return SizedBox(
            width: widths[i],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                tr(headers[i]),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF374151),
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

  List<String> _textCells(MobileAttendanceShiftVerticalRow row) {
    final cells = <String>[row.day, row.weekday];
    for (var i = 0; i < shiftHourLabels.length; i++) {
      cells.add(i < row.shiftHours.length ? row.shiftHours[i] : '—');
    }
    cells.add(row.totalWork);
    cells.add(row.totalHours);
    if (showTravel) cells.add(row.travelHours);
    cells.addAll([row.late, row.early, row.overtime]);
    return cells;
  }

  Color _cellColor(int textIndex, String value, {required bool total}) {
    if (value == '—') {
      return total ? const Color(0xFF1E40AF) : const Color(0xFF18181B);
    }
    final n = shiftHourLabels.length;
    if (textIndex >= 0 && textIndex < n) {
      return const Color(0xFF0F766E);
    }
    var idx = n;
    if (textIndex == idx) {
      return total ? const Color(0xFF1D4ED8) : const Color(0xFF2563EB);
    }
    idx++;
    if (textIndex == idx) {
      return total ? const Color(0xFF15803D) : const Color(0xFF16A34A);
    }
    idx++;
    if (showTravel) {
      if (textIndex == idx) return const Color(0xFFEA580C);
      idx++;
    }
    if (textIndex == idx) return const Color(0xFFF59E0B);
    idx++;
    if (textIndex == idx) return const Color(0xFFEF4444);
    idx++;
    if (textIndex == idx) return const Color(0xFF8B5CF6);
    return total ? const Color(0xFF1E40AF) : const Color(0xFF18181B);
  }

  Widget _buildDataRow(MobileAttendanceShiftVerticalRow row, int index) {
    final bg = row.isToday
        ? _todayBg
        : (index.isEven ? const Color(0xFFF9FAFB) : Colors.white);
    final texts = _textCells(row);
    final widths = _colWidths;
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
            width: widths[0],
            child: _textCell(texts[0], row.isToday),
          ),
          SizedBox(
            width: widths[1],
            child: _textCell(texts[1], row.isToday),
          ),
          SizedBox(width: widths[2], child: row.attendance),
          for (var i = 3; i < widths.length; i++)
            SizedBox(
              width: widths[i],
              child: _textCell(
                texts[i - 1],
                row.isToday,
                color: _cellColor(i - 3, texts[i - 1], total: false),
                bold: row.isToday,
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
    final texts = _textCells(row);
    final widths = _colWidths;
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
            width: widths[0],
            child: _textCell(texts[0], false, bold: true),
          ),
          SizedBox(
            width: widths[1],
            child: _textCell(texts[1], false, bold: true),
          ),
          SizedBox(width: widths[2], child: row.attendance),
          for (var i = 3; i < widths.length; i++)
            SizedBox(
              width: widths[i],
              child: _textCell(
                texts[i - 1],
                false,
                bold: true,
                color: _cellColor(i - 3, texts[i - 1], total: true),
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

  static const _headerBg = Color(0xFFF4F6F8);
  static const _accent = PosTheme.kiotBlue;
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
                          size: 18, color: _accent),
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
                right: BorderSide(color: Color(0xFFE5E7EB)),
                bottom: BorderSide(color: Color(0xFFE5E7EB), width: 0.5),
              ),
            ),
            child: Text(tr('Nhân viên'),
              style: TextStyle(
                color: Color(0xFF374151),
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
                    color: Color(0xFF374151),
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
