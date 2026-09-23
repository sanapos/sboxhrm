import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:excel/excel.dart' as excel_lib;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../widgets/hrm_page_chrome.dart';
import '../widgets/notification_overlay.dart';
import 'branch_filter_helper.dart';
import 'department_filter_helper.dart';
import 'vietnamese_font.dart';
import 'excel_report_builder.dart';
import 'excel_bytes_utils.dart';
import 'excel_download_helper.dart';
import 'file_saver.dart' as file_saver;
import 'web_canvas.dart' as web_canvas;
import 'package:zkteco_flutter_client/l10n/app_tr.dart';
import 'package:zkteco_flutter_client/l10n/app_ui_locale.dart';

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
      locale: appUiLocale(),
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
        label: Text(tr(label),
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
                    tr(isCustom
                        ? rangeText
                        : ReportDateRangePresets.presetLabel('custom')),
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
                        tr(rangeText),
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
                        tr(ReportDateRangePresets.presetLabel(preset)),
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
  List<Map<String, dynamic>> departments = [];
  List<Map<String, dynamic>> employees = [];
  bool branchesLoaded = false;
  bool departmentsLoaded = false;
  bool employeesLoaded = false;
  bool employeesLoading = false;
  String? _employeesLoadedForBranch;

  Future<void> loadOrgFilters(ApiService api) async {
    await Future.wait([loadBranches(api), loadDepartments(api)]);
  }

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

  Future<void> loadDepartments(ApiService api) async {
    if (departmentsLoaded) return;
    try {
      final res = await api.getDepartmentsForSelect();
      final data = res['data'];
      if (data is List) {
        departments =
            data.map((d) => Map<String, dynamic>.from(d as Map)).toList();
      }
    } catch (_) {}
    departmentsLoaded = true;
  }

  /// Tải NV — khi [branchId] đổi sẽ tải lại theo chi nhánh (+ con) từ server.
  Future<void> ensureEmployees(ApiService api, {String? branchId}) async {
    final key = branchId ?? '';
    if (employeesLoaded &&
        !employeesLoading &&
        _employeesLoadedForBranch == key) {
      return;
    }
    employeesLoading = true;
    try {
      final emps = await api.getEmployeesForSelect(
        pageSize: 500,
        branchId: branchId,
        includeChildBranches: true,
      );
      employees =
          emps.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      if (employees.isEmpty && branchId == null) {
        final me = await api.getMyEmployee();
        if (me['isSuccess'] == true && me['data'] is Map) {
          employees = [Map<String, dynamic>.from(me['data'] as Map)];
        }
      }
      employeesLoaded = true;
      _employeesLoadedForBranch = key;
    } catch (_) {}
    employeesLoading = false;
  }

  Set<String> _branchIdsIncludingChildren(String? branchId) {
    if (branchId == null || branchId.isEmpty) return {};
    return BranchFilterHelper.expandBranchIds(
      branchId,
      branches,
      includeChildren: true,
    );
  }

  Set<String> userIdsForBranch(String? branchId) {
    if (branchId == null) return {};
    final ids = _branchIdsIncludingChildren(branchId);
    if (ids.isEmpty) return {};
    return BranchFilterHelper.employeeKeysForBranches(employees, ids);
  }

  Set<String> codesForBranch(String? branchId) {
    if (branchId == null) return {};
    final ids = _branchIdsIncludingChildren(branchId);
    if (ids.isEmpty) return {};
    return BranchFilterHelper.employeeCodesInBranches(employees, ids);
  }

  Set<String> _departmentIdsIncludingChildren(String? departmentId) {
    if (departmentId == null || departmentId.isEmpty) return {};
    return DepartmentFilterHelper.expandDepartmentIds(
      departmentId,
      departments,
      includeChildren: true,
    );
  }

  Set<String> userIdsForDepartment(String? departmentId) {
    if (departmentId == null) return {};
    final ids = _departmentIdsIncludingChildren(departmentId);
    if (ids.isEmpty) return {};
    return DepartmentFilterHelper.employeeKeysForDepartments(
      employees,
      ids,
      departments,
    );
  }

  Set<String> codesForDepartment(String? departmentId) {
    if (departmentId == null) return {};
    final ids = _departmentIdsIncludingChildren(departmentId);
    if (ids.isEmpty) return {};
    return DepartmentFilterHelper.employeeCodesInDepartments(
      employees,
      ids,
      departments,
    );
  }

  /// null = không lọc chi nhánh/phòng ban. Tập rỗng = không khớp NV nào.
  Set<String>? scopeUserIds({String? branchId, String? departmentId}) {
    Set<String>? ids;
    if (branchId != null && branchId.isNotEmpty) {
      ids = userIdsForBranch(branchId);
    }
    if (departmentId != null && departmentId.isNotEmpty) {
      final d = userIdsForDepartment(departmentId);
      ids = ids == null ? d : ids.intersection(d);
    }
    return ids;
  }

  Set<String>? scopeCodes({String? branchId, String? departmentId}) {
    Set<String>? codes;
    if (branchId != null && branchId.isNotEmpty) {
      codes = codesForBranch(branchId);
    }
    if (departmentId != null && departmentId.isNotEmpty) {
      final d = codesForDepartment(departmentId);
      codes = codes == null ? d : codes.intersection(d);
    }
    return codes;
  }

  /// NV trong phạm vi chi nhánh ∩ phòng ban. `null` = không lọc tổ chức.
  List<Map<String, dynamic>>? scopedEmployees({
    String? branchId,
    String? departmentId,
  }) {
    final ids = scopeUserIds(branchId: branchId, departmentId: departmentId);
    if (ids == null) return null;
    if (ids.isEmpty) return const [];
    return employees.where((e) {
      final id = e['id']?.toString() ?? '';
      final userId = e['applicationUserId']?.toString() ?? '';
      return (id.isNotEmpty && ids.contains(id)) ||
          (userId.isNotEmpty && ids.contains(userId));
    }).toList();
  }

  /// Mã NV, PIN, id hồ sơ, user id — khớp log chấm công và dòng báo cáo.
  Set<String>? scopeIdentityKeys({String? branchId, String? departmentId}) {
    final scoped =
        scopedEmployees(branchId: branchId, departmentId: departmentId);
    if (scoped == null) return null;
    final keys = <String>{};
    for (final e in scoped) {
      for (final field in const [
        'employeeCode',
        'pin',
        'Pin',
        'id',
        'applicationUserId',
      ]) {
        final v = e[field]?.toString() ?? '';
        if (v.isNotEmpty && v != 'null') keys.add(v);
      }
    }
    return keys;
  }

  bool mapRowInScope(
    Map<String, dynamic> row, {
    String? branchId,
    String? departmentId,
  }) {
    final keys =
        scopeIdentityKeys(branchId: branchId, departmentId: departmentId);
    if (keys == null) return true;
    if (keys.isEmpty) return false;
    for (final field in const [
      'employeeUserId',
      'EmployeeUserId',
      'employeeId',
      'EmployeeId',
      'applicationUserId',
      'id',
      'employeeCode',
      'EmployeeCode',
      'pin',
    ]) {
      final v = row[field]?.toString() ?? '';
      if (v.isNotEmpty && keys.contains(v)) return true;
    }
    return false;
  }

  List<Map<String, dynamic>> filterEmployeeRows(
    List<Map<String, dynamic>> rows, {
    String? branchId,
    String? departmentId,
  }) {
    return rows
        .where((e) => mapRowInScope(
              e,
              branchId: branchId,
              departmentId: departmentId,
            ))
        .toList();
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
            Text(tr(title),
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade700),
                textAlign: TextAlign.center),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(tr(subtitle!),
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
          title: 'Thông báo', message: tr('Không có dữ liệu để xuất'));
      return false;
    }
    try {
      final fn = normalizeExportFileName(
        '${filePrefix}_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.xlsx',
      );
      final download = ExcelDownloadHelper();
      await download.prepareSave(fn);

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
      final bytes = ExcelReportBuilder.encodeReport(wb);
      if (bytes == null) return false;
      if (!isValidXlsxBytes(bytes)) {
        if (context.mounted) {
          NotificationOverlayManager().showError(
            title: 'Lỗi',
            message: tr('Không tạo được file Excel hợp lệ.'),
          );
        }
        return false;
      }
      await download.saveBytes(bytes, fn);
      if (context.mounted) {
        NotificationOverlayManager()
            .showSuccess(title: 'Xuất Excel', message: tr('Đã lưu vào Tải về/SBOX HRM: $fn'));
      }
      return true;
    } catch (e) {
      if (context.mounted) {
        NotificationOverlayManager()
            .showError(title: 'Lỗi', message: tr('Không thể xuất Excel: $e'));
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

/// Chụp [RepaintBoundary] (qua [GlobalKey]) thành file PNG.
class ClientPngExport {
  static Future<bool> capture({
    required BuildContext context,
    required GlobalKey key,
    required String filePrefix,
    double pixelRatio = 2.5,
  }) async {
    try {
      await WidgetsBinding.instance.endOfFrame;
      final boundary =
          key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        NotificationOverlayManager().showWarning(
            title: 'Xuất PNG',
            message: tr('Không tìm thấy nội dung báo cáo để chụp'));
        return false;
      }
      final size = boundary.size;
      var ratio = pixelRatio;
      final maxSide = math.max(size.width, size.height);
      // Web/canvas: ảnh quá cao bị cắt hoặc toImage lỗi — hạ tỉ lệ.
      final cap = kIsWeb ? 8192.0 : 16384.0;
      if (maxSide > 0) {
        ratio = math.min(pixelRatio, cap / maxSide);
        if (ratio < 0.8) ratio = 0.8;
      }
      late final ui.Image image;
      try {
        image = await boundary.toImage(pixelRatio: ratio);
      } catch (_) {
        image = await boundary.toImage(pixelRatio: math.min(ratio, 1.0));
      }
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        NotificationOverlayManager().showError(
            title: 'Xuất PNG', message: tr('Không thể tạo ảnh'));
        return false;
      }
      final pngBytes = byteData.buffer.asUint8List();
      final fileName = normalizeExportFileName(
        '${filePrefix}_${DateFormat('ddMMyyyy_HHmm').format(DateTime.now())}.png',
      );
      await file_saver.saveAndOpenFileBytes(pngBytes, fileName, 'image/png');
      if (context.mounted) {
        NotificationOverlayManager().showSuccess(
            title: 'Xuất PNG',
            message: tr('Đã lưu vào Ảnh/SBOX HRM: $fileName'));
      }
      return true;
    } catch (e) {
      if (context.mounted) {
        NotificationOverlayManager()
            .showError(title: 'Xuất PNG', message: tr('Lỗi xuất PNG: $e'));
      }
      return false;
    }
  }

  /// Vẽ bảng ra PNG giống Tổng hợp lương. Chụp widget trên web lỗi khi bảng dài.
  static Future<bool> table({
    required BuildContext context,
    required String title,
    required String filePrefix,
    required List<String> headers,
    required List<List<dynamic>> rows,
    String? periodLabel,
    List<String> summaryLines = const [],
  }) async {
    if (rows.isEmpty || headers.isEmpty) {
      NotificationOverlayManager().showError(
          title: 'Thông báo', message: tr('Không có dữ liệu để xuất'));
      return false;
    }
    try {
      final cellRows = [
        for (final row in rows) [for (final cell in row) _pngCell(cell)],
      ];
      final colCount = headers.length;
      final raw = List<double>.filled(colCount, 64);
      for (var c = 0; c < colCount; c++) {
        var w = headers[c].length * 8.0 + 28;
        for (final row in cellRows) {
          if (c >= row.length) continue;
          final cw = row[c].length * 7.2 + 20;
          if (cw > w) w = cw;
        }
        raw[c] = w.clamp(56, 240);
      }
      final natural = raw.fold<double>(0, (s, w) => s + w);
      const pad = 16.0;
      var tableWidth = math.max(960.0, natural);
      const maxCanvas = 8000.0;
      if (tableWidth + pad * 2 > maxCanvas) {
        tableWidth = maxCanvas - pad * 2;
      }
      final scale = tableWidth / natural;
      final colWidths = [for (final w in raw) w * scale];

      const titleH = 36.0;
      const lineH = 20.0;
      var metaH = 0.0;
      if (periodLabel != null && periodLabel.isNotEmpty) metaH += lineH;
      metaH += summaryLines.where((s) => s.trim().isNotEmpty).length * lineH;
      if (metaH > 0) metaH += 6;
      const headerH = 32.0;
      var rowH = 26.0;
      final body =  pad + titleH + metaH + 8 + headerH + rows.length * rowH + pad;
      if (body > maxCanvas) {
        rowH = ((maxCanvas - (body - rows.length * rowH)) / rows.length)
            .clamp(16.0, 26.0);
      }
      final totalHeight =
          pad + titleH + metaH + 8 + headerH + rows.length * rowH + pad;
      final totalWidth = tableWidth + pad * 2;

      void draw(dynamic ctx) {
        ctx.fillStyle = '#FFFFFF';
        ctx.fillRect(0, 0, totalWidth, totalHeight);
        var y = pad;
        ctx.fillStyle = '#1E1B4B';
        ctx.font = 'bold 18px Arial';
        ctx.textAlign = 'left';
        ctx.fillText(title, pad, y + 22);
        y += titleH;
        ctx.fillStyle = '#52525B';
        ctx.font = '12px Arial';
        if (periodLabel != null && periodLabel.isNotEmpty) {
          ctx.fillText(periodLabel, pad, y + 14);
          y += lineH;
        }
        for (final line in summaryLines) {
          if (line.trim().isEmpty) continue;
          ctx.fillText(line, pad, y + 14);
          y += lineH;
        }
        if (metaH > 0) y += 6;
        final tableTop = y;
        ctx.fillStyle = '#6366F1';
        ctx.fillRect(pad, tableTop, tableWidth, headerH);
        ctx.fillStyle = '#FFFFFF';
        ctx.font = 'bold 11px Arial';
        ctx.textAlign = 'center';
        var x = pad;
        for (var c = 0; c < colCount; c++) {
          ctx.fillText(headers[c], x + colWidths[c] / 2, tableTop + 21);
          x += colWidths[c];
        }
        y = tableTop + headerH;
        ctx.font = '11px Arial';
        ctx.textAlign = 'center';
        for (var r = 0; r < cellRows.length; r++) {
          ctx.fillStyle = r.isEven ? '#F8FAFC' : '#FFFFFF';
          ctx.fillRect(pad, y, tableWidth, rowH);
          ctx.fillStyle = '#18181B';
          x = pad;
          final row = cellRows[r];
          for (var c = 0; c < colCount; c++) {
            final text = c < row.length ? row[c] : '';
            ctx.fillText(text, x + colWidths[c] / 2, y + rowH * 0.72);
            x += colWidths[c];
          }
          y += rowH;
        }
        ctx.strokeStyle = '#CBD5E1';
        ctx.lineWidth = 1;
        ctx.strokeRect(pad, tableTop, tableWidth, y - tableTop);
        ctx.textAlign = 'left';
      }

      final fileName = normalizeExportFileName(
        '${filePrefix}_${DateFormat('ddMMyyyy_HHmm').format(DateTime.now())}.png',
      );
      final dataUrl = web_canvas.renderToPngDataUrl(
        width: totalWidth.ceil(),
        height: totalHeight.ceil(),
        draw: draw,
      );
      if (dataUrl != null) {
        await file_saver.saveAndOpenDataUrl(dataUrl, fileName);
      } else {
        final pngBytes = await web_canvas.renderToPngBytes(
          width: totalWidth.ceil(),
          height: totalHeight.ceil(),
          draw: draw,
        );
        if (pngBytes == null) {
          NotificationOverlayManager().showError(
              title: 'Xuất PNG', message: tr('Không thể tạo ảnh'));
          return false;
        }
        await file_saver.saveAndOpenFileBytes(pngBytes, fileName, 'image/png');
      }
      if (context.mounted) {
        NotificationOverlayManager().showSuccess(
            title: 'Xuất PNG',
            message: tr('Đã lưu vào Ảnh/SBOX HRM: $fileName'));
      }
      return true;
    } catch (e) {
      if (context.mounted) {
        NotificationOverlayManager()
            .showError(title: 'Xuất PNG', message: tr('Lỗi xuất PNG: $e'));
      }
      return false;
    }
  }

  static String _pngCell(dynamic v) {
    if (v == null) return '';
    if (v is bool) return v ? 'Có' : '';
    if (v is num) {
      final d = v.toDouble();
      if (d.isNaN || d.isInfinite) return '';
      if (d == d.roundToDouble()) {
        return NumberFormat('#,##0', 'vi_VN').format(d.round());
      }
      return NumberFormat('#,##0.0', 'vi_VN')
          .format(double.parse(d.toStringAsFixed(1)));
    }
    return v.toString();
  }
}
