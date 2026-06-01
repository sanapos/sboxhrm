import 'dart:convert';

import 'package:excel/excel.dart' as excel_lib;
import 'package:intl/intl.dart';

/// Export metadata decoded from JWT or explicit user fields.
class ExcelReportContext {
  final String? storeName;
  final String? exportedBy;

  const ExcelReportContext({this.storeName, this.exportedBy});

  static ExcelReportContext fromJwt(String? token) {
    if (token == null || token.isEmpty) return const ExcelReportContext();
    try {
      final parts = token.split('.');
      if (parts.length != 3) return const ExcelReportContext();
      final normalized = base64Url.normalize(parts[1]);
      final claims =
          json.decode(utf8.decode(base64Url.decode(normalized)))
              as Map<String, dynamic>;
      final email = claims[
              'http://schemas.xmlsoap.org/ws/2005/05/identity/claims/emailaddress']
          ?.toString();
      final name = claims[
              'http://schemas.xmlsoap.org/ws/2005/05/identity/claims/name']
          ?.toString();
      final store = claims['storeName']?.toString().trim();
      return ExcelReportContext(
        storeName: store != null && store.isNotEmpty ? store : null,
        exportedBy: (email != null && email.isNotEmpty)
            ? email
            : (name != null && name.isNotEmpty ? name : null),
      );
    } catch (_) {
      return const ExcelReportContext();
    }
  }

  static ExcelReportContext fromUser({
    String? storeName,
    String? email,
    String? fullName,
  }) {
    return ExcelReportContext(
      storeName: storeName?.trim().isEmpty == true ? null : storeName?.trim(),
      exportedBy: (email != null && email.isNotEmpty)
          ? email
          : (fullName != null && fullName.isNotEmpty ? fullName : null),
    );
  }

  /// App user fields override JWT claims when present.
  static ExcelReportContext resolve({
    String? token,
    String? storeName,
    String? email,
    String? fullName,
  }) {
    final jwt = fromJwt(token);
    final s = storeName?.trim();
    final e = email?.trim();
    final n = fullName?.trim();
    return ExcelReportContext(
      storeName: (s != null && s.isNotEmpty) ? s : jwt.storeName,
      exportedBy: (e != null && e.isNotEmpty)
          ? e
          : ((n != null && n.isNotEmpty) ? n : jwt.exportedBy),
    );
  }
}

/// Standard title / store / filter / export-time block for client-side Excel exports.
class ExcelReportBuilder {
  static const _headerFill = '#6366F1';

  static excel_lib.CellStyle headerStyle() => excel_lib.CellStyle(
        bold: true,
        backgroundColorHex: excel_lib.ExcelColor.fromHexString(_headerFill),
        fontColorHex: excel_lib.ExcelColor.white,
        horizontalAlign: excel_lib.HorizontalAlign.Center,
        verticalAlign: excel_lib.VerticalAlign.Center,
        fontSize: 11,
      );

  static excel_lib.CellStyle titleStyle() => excel_lib.CellStyle(
        bold: true,
        fontSize: 16,
        horizontalAlign: excel_lib.HorizontalAlign.Center,
      );

  static excel_lib.Excel createWorkbook({
    required String sheetName,
    bool deleteDefaultSheet = true,
  }) {
    final wb = excel_lib.Excel.createExcel();
    wb[sheetName];
    if (deleteDefaultSheet && wb.sheets.containsKey('Sheet1')) {
      wb.delete('Sheet1');
    }
    return wb;
  }

  /// Returns 0-based row indices: header row and first data row.
  static ({int headerRow, int dataStartRow}) applyMeta(
    excel_lib.Sheet sheet, {
    required String title,
    required int columnCount,
    String? storeName,
    String? periodLabel,
    String? filterLabel,
    String? exportedBy,
    List<String> summaryLines = const [],
    int? rowCount,
  }) {
    final cols = columnCount < 1 ? 1 : columnCount;
    var row = 0;

    void setMergedLine(int r, String text, {excel_lib.CellStyle? style}) {
      final cell = sheet.cell(
        excel_lib.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r),
      );
      cell.value = excel_lib.TextCellValue(text);
      if (style != null) cell.cellStyle = style;
      if (cols > 1) {
        sheet.merge(
          excel_lib.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r),
          excel_lib.CellIndex.indexByColumnRow(
              columnIndex: cols - 1, rowIndex: r),
        );
      }
    }

    setMergedLine(row++, title, style: titleStyle());

    if (storeName != null && storeName.isNotEmpty) {
      setMergedLine(row++, 'Cửa hàng: $storeName');
    }

    final periodFilter = <String>[];
    if (periodLabel != null && periodLabel.isNotEmpty) {
      periodFilter.add('Kỳ dữ liệu: $periodLabel');
    }
    if (filterLabel != null && filterLabel.isNotEmpty) {
      periodFilter.add('Bộ lọc: $filterLabel');
    }
    if (periodFilter.isNotEmpty) {
      setMergedLine(row++, periodFilter.join('  |  '));
    }

    final exportedAt =
        DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now());
    var exportLine = 'Xuất lúc: $exportedAt';
    if (exportedBy != null && exportedBy.isNotEmpty) {
      exportLine += '  |  Người xuất: $exportedBy';
    }
    if (rowCount != null) {
      exportLine += '  |  Số dòng: $rowCount';
    }
    setMergedLine(row++, exportLine);

    for (final line in summaryLines) {
      if (line.trim().isEmpty) continue;
      setMergedLine(row++, line);
    }

    row++; // spacer
    final headerRow = row;
    return (headerRow: headerRow, dataStartRow: headerRow + 1);
  }

  static void writeRow(
    excel_lib.Sheet sheet,
    int row,
    List<excel_lib.CellValue?> values,
  ) {
    for (var i = 0; i < values.length; i++) {
      final v = values[i];
      if (v == null) continue;
      sheet
          .cell(excel_lib.CellIndex.indexByColumnRow(
              columnIndex: i, rowIndex: row))
          .value = v;
    }
  }

  static void applyHeaderRow(
    excel_lib.Sheet sheet,
    int headerRow,
    List<String> headers, {
    excel_lib.CellStyle? style,
  }) {
    final hdrStyle = style ?? headerStyle();
    for (var i = 0; i < headers.length; i++) {
      final cell = sheet.cell(
        excel_lib.CellIndex.indexByColumnRow(
            columnIndex: i, rowIndex: headerRow),
      );
      cell.value = excel_lib.TextCellValue(headers[i]);
      cell.cellStyle = hdrStyle;
    }
  }
}
