import 'package:excel/excel.dart' as excel_lib;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../widgets/hrm_page_chrome.dart';
import '../widgets/notification_overlay.dart';
import 'vietnamese_font.dart';
import 'excel_report_builder.dart';
import 'file_saver.dart' as file_saver;

/// Khoảng ngày theo preset (dùng chung cho màn báo cáo).
class ReportDateRangePresets {
  ReportDateRangePresets._();

  static DateTime _todayDate() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  static ({DateTime from, DateTime to}) resolve(String preset) {
    final today = _todayDate();
    switch (preset) {
      case 'today':
        return (from: today, to: today);
      case 'yesterday':
        final y = today.subtract(const Duration(days: 1));
        return (from: y, to: y);
      case 'this_week':
        final weekStart = today.subtract(Duration(days: today.weekday - 1));
        return (from: weekStart, to: today);
      case 'last_week':
        final weekStart = today.subtract(Duration(days: today.weekday - 1));
        final lastStart = weekStart.subtract(const Duration(days: 7));
        final lastEnd = weekStart.subtract(const Duration(days: 1));
        return (from: lastStart, to: lastEnd);
      case 'last_month':
        final firstThis = DateTime(today.year, today.month, 1);
        final lastDayPrev = firstThis.subtract(const Duration(days: 1));
        final firstPrev = DateTime(lastDayPrev.year, lastDayPrev.month, 1);
        return (from: firstPrev, to: lastDayPrev);
      case 'this_month':
      default:
        return (from: DateTime(today.year, today.month, 1), to: today);
    }
  }

  static String presetLabel(String preset) {
    switch (preset) {
      case 'today':
        return 'Hôm nay';
      case 'yesterday':
        return 'Hôm qua';
      case 'this_week':
        return 'Tuần này';
      case 'last_week':
        return 'Tuần trước';
      case 'last_month':
        return 'Tháng trước';
      case 'custom':
        return 'Tùy chọn khác';
      case 'this_month':
      default:
        return 'Tháng này';
    }
  }
}

/// Chips preset + một dòng khoảng ngày (không tràn ô Từ/Đến).
class ReportDateRangeFilterBar extends StatelessWidget {
  final DateTime from;
  final DateTime to;
  final String preset;
  final void Function(DateTime from, DateTime to, String preset) onChanged;
  /// Ẩn dòng lịch thứ hai — gọn hơn trên mobile.
  final bool compact;

  const ReportDateRangeFilterBar({
    super.key,
    required this.from,
    required this.to,
    required this.preset,
    required this.onChanged,
    this.compact = false,
  });

  Future<void> _pickCustomRange(BuildContext context) async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: DateTimeRange(start: from, end: to),
      locale: const Locale('vi'),
    );
    if (picked != null) {
      onChanged(picked.start, picked.end, 'custom');
    }
  }

  void _applyPreset(BuildContext context, String p) {
    if (p == 'custom') {
      _pickCustomRange(context);
      return;
    }
    final r = ReportDateRangePresets.resolve(p);
    onChanged(r.from, r.to, p);
  }

  Widget _chip(BuildContext context, String key, String label) {
    final selected = preset == key;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(label,
            style: vietnameseTextStyle(const TextStyle(fontSize: 12))),
        selected: selected,
        onSelected: (_) => _applyPreset(context, key),
        backgroundColor: Colors.white,
        selectedColor: HrmPageChrome.primaryNavy,
        labelStyle: TextStyle(
          color: selected ? Colors.white : const Color(0xFF18181B),
        ),
        side: const BorderSide(color: Color(0xFFE4E4E7)),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('dd/MM/yyyy');
    final rangeText = '${fmt.format(from)} - ${fmt.format(to)}';
    final isCustom = preset == 'custom';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _chip(context, 'today', 'Hôm nay'),
              _chip(context, 'yesterday', 'Hôm qua'),
              _chip(context, 'this_week', 'Tuần này'),
              _chip(context, 'last_week', 'Tuần trước'),
              _chip(context, 'this_month', 'Tháng này'),
              _chip(context, 'last_month', 'Tháng trước'),
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ActionChip(
                  avatar: Icon(
                    Icons.date_range,
                    size: 16,
                    color: isCustom ? Colors.white : const Color(0xFF6B7280),
                  ),
                  label: Text(
                    isCustom
                        ? rangeText
                        : ReportDateRangePresets.presetLabel('custom'),
                    style: TextStyle(
                      fontSize: 12,
                      color: isCustom ? Colors.white : const Color(0xFF18181B),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  backgroundColor:
                      isCustom ? HrmPageChrome.primaryNavy : Colors.white,
                  side: const BorderSide(color: Color(0xFFE4E4E7)),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _pickCustomRange(context),
                ),
              ),
            ],
          ),
        ),
        if (!compact) ...[
          const SizedBox(height: 6),
          Material(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              onTap: () => _pickCustomRange(context),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFE4E4E7)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_month_outlined,
                        size: 18, color: Color(0xFF6B7280)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        rangeText,
                        style: vietnameseTextStyle(const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF111827),
                        )),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (!isCustom) ...[
                      const SizedBox(width: 6),
                      Text(
                        ReportDateRangePresets.presetLabel(preset),
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF9CA3AF),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Lazy branch/employee lists for report filters (avoids 1000-employee preload).
class ReportBranchFilter {
  List<Map<String, dynamic>> branches = [];
  List<Map<String, dynamic>> employees = [];
  bool branchesLoaded = false;
  bool employeesLoaded = false;
  bool employeesLoading = false;

  Future<void> loadBranches(ApiService api) async {
    if (branchesLoaded) return;
    try {
      final br = await api.getBranchesForSelect();
      final bd = br['data'];
      if (bd is List) {
        branches = bd.map((b) => Map<String, dynamic>.from(b as Map)).toList();
      }
    } catch (_) {}
    branchesLoaded = true;
  }

  Future<void> ensureEmployees(ApiService api) async {
    if (employeesLoaded || employeesLoading) return;
    employeesLoading = true;
    try {
      final emps = await api.getEmployees(pageSize: 500);
      employees =
          emps.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      if (employees.isEmpty) {
        final me = await api.getMyEmployee();
        if (me['isSuccess'] == true && me['data'] is Map) {
          employees = [Map<String, dynamic>.from(me['data'] as Map)];
        }
      }
      employeesLoaded = true;
    } catch (_) {}
    employeesLoading = false;
  }

  Set<String> userIdsForBranch(String? branchId) {
    if (branchId == null) return {};
    return employees
        .where((e) => e['branchId']?.toString() == branchId)
        .map((e) => e['id']?.toString() ?? '')
        .where((s) => s.isNotEmpty)
        .toSet();
  }

  Set<String> codesForBranch(String? branchId) {
    if (branchId == null) return {};
    return employees
        .where((e) => e['branchId']?.toString() == branchId)
        .map((e) => e['employeeCode']?.toString() ?? '')
        .where((s) => s.isNotEmpty)
        .toSet();
  }
}

class ReportEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;

  const ReportEmptyState({
    super.key,
    this.icon = Icons.inbox_outlined,
    required this.title,
    this.subtitle,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text(title,
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade700),
                textAlign: TextAlign.center),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(subtitle!,
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                  textAlign: TextAlign.center),
            ],
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}

/// Client-side .xlsx with standard SBOX header block.
class ClientExcelExport {
  static Future<bool> export({
    required BuildContext context,
    required String title,
    required String sheetName,
    required String filePrefix,
    required List<String> headers,
    required List<List<dynamic>> rows,
    String? periodLabel,
    String? filterLabel,
    List<String> summaryLines = const [],
  }) async {
    if (rows.isEmpty) {
      NotificationOverlayManager().showError(
          title: 'Thông báo', message: 'Không có dữ liệu để xuất');
      return false;
    }
    try {
      final wb = ExcelReportBuilder.createWorkbook(sheetName: sheetName);
      final sh = wb[sheetName];
      final auth = context.read<AuthProvider>();
      final exportCtx = ExcelReportContext.resolve(
        token: auth.token,
        email: auth.user?.email,
        fullName: auth.user?.fullName,
      );
      final layout = ExcelReportBuilder.applyMeta(
        sh,
        title: title,
        columnCount: headers.length,
        storeName: exportCtx.storeName,
        periodLabel: periodLabel,
        filterLabel: filterLabel,
        exportedBy: exportCtx.exportedBy,
        summaryLines: summaryLines,
        rowCount: rows.length,
      );
      ExcelReportBuilder.applyHeaderRow(sh, layout.headerRow, headers);
      var rowIdx = layout.dataStartRow;
      for (final row in rows) {
        ExcelReportBuilder.writeRow(
          sh,
          rowIdx++,
          row.map(_cell).toList(),
        );
      }
      final bytes = wb.encode();
      if (bytes == null) return false;
      final fn =
          '${filePrefix}_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.xlsx';
      await file_saver.saveFileBytes(
        bytes,
        fn,
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        category: 'Báo cáo',
        sourceModule: filePrefix,
      );
      if (context.mounted) {
        NotificationOverlayManager()
            .showSuccess(title: 'Xuất Excel', message: 'Đã lưu vào Tải về/SBOX HRM: $fn');
      }
      return true;
    } catch (e) {
      if (context.mounted) {
        NotificationOverlayManager()
            .showError(title: 'Lỗi', message: 'Không thể xuất Excel: $e');
      }
      return false;
    }
  }

  static excel_lib.CellValue? _cell(dynamic v) {
    if (v == null) return null;
    if (v is int) return excel_lib.IntCellValue(v);
    if (v is double) return excel_lib.DoubleCellValue(v);
    if (v is num) return excel_lib.DoubleCellValue(v.toDouble());
    if (v is bool) return excel_lib.BoolCellValue(v);
    return excel_lib.TextCellValue(v.toString());
  }
}
