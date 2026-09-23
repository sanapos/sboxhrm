import 'dart:convert';

import 'package:archive/archive.dart';
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
        textWrapping: excel_lib.TextWrapping.WrapText,
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

  static const _headerAbbrev = <String, String>{
    'Phương thức thanh toán': 'PT thanh toán',
    'Tên nhân viên': 'Tên NV',
    'Mã nhân viên': 'Mã NV',
    'Số điện thoại': 'SĐT',
    'Người liên hệ': 'Người LH',
    'Ghi chú nội bộ': 'Ghi chú NB',
    'Ngày giao dịch': 'Ngày GD',
    'Giờ thập phân': 'Giờ TP',
    'Lương hoàn thành': 'Lương HT',
    'Lương theo công': 'Lương công',
    'Lương theo ngày': 'Lương ngày',
    'Lương tăng ca': 'Lương TC',
    'Lương cơ bản': 'Lương CB',
    'Lương theo giờ': 'Lương giờ',
    'Lương theo ca': 'Lương ca',
    'Tên trong máy': 'Tên máy',
    'Tên thiết bị': 'Thiết bị',
    'Họ và tên': 'Họ tên',
    'Mã thẻ từ': 'Mã thẻ',
    'Điện thoại': 'SĐT',
    'thanh toán': 'TT',
    'Thanh toán': 'TT',
  };

  /// Xuống dòng, viết tắt khi tiêu đề dài hơn bề rộng cột.
  static String compactHeader(String raw, {int maxLine = 10}) {
    final clean =
        raw.replaceAll('\n', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    if (clean.isEmpty) return raw;
    final cap = maxLine < 4 ? 4 : maxLine;
    final wrapped = _wrapHeader(clean, cap);
    if (wrapped != null) return wrapped;
    final short = _abbreviateHeader(clean);
    final wrappedShort = _wrapHeader(short, cap);
    if (wrappedShort != null) return wrappedShort;
    return _wrapHeaderLoose(short);
  }

  static String _abbreviateHeader(String input) {
    var s = input;
    final keys = _headerAbbrev.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final key in keys) {
      s = s.replaceAll(key, _headerAbbrev[key]!);
    }
    return s;
  }

  static String? _wrapHeader(String text, int cap) {
    if (text.length <= cap) return text;
    final words = text.split(' ');
    if (words.length < 2) return null;
    String? best;
    var bestScore = 1 << 30;
    for (var i = 1; i < words.length; i++) {
      final left = words.sublist(0, i).join(' ');
      final right = words.sublist(i).join(' ');
      if (left.length > cap || right.length > cap) continue;
      final score = (left.length - right.length).abs();
      if (score < bestScore) {
        bestScore = score;
        best = '$left\n$right';
      }
    }
    return best;
  }

  static String _wrapHeaderLoose(String text) {
    final words = text.split(' ');
    if (words.length < 2) return text;
    var best = 1;
    var bestMax = 1 << 30;
    for (var i = 1; i < words.length; i++) {
      final left = words.sublist(0, i).join(' ').length;
      final right = words.sublist(i).join(' ').length;
      final maxLen = left > right ? left : right;
      if (maxLen < bestMax) {
        bestMax = maxLen;
        best = i;
      }
    }
    return '${words.sublist(0, best).join(' ')}\n${words.sublist(best).join(' ')}';
  }

  static void applyHeaderRow(
    excel_lib.Sheet sheet,
    int headerRow,
    List<String> headers, {
    excel_lib.CellStyle? style,
  }) {
    final hdrStyle = (style ?? headerStyle()).copyWith(
      textWrappingVal: excel_lib.TextWrapping.WrapText,
      verticalAlignVal: excel_lib.VerticalAlign.Center,
    );
    final font = hdrStyle.fontSize ?? 11;
    var lines = 1;
    for (var i = 0; i < headers.length; i++) {
      final incoming = headers[i];
      final compact = incoming.contains('\n')
          ? incoming
          : compactHeader(incoming);
      if (compact.contains('\n')) lines = 2;
      final cell = sheet.cell(
        excel_lib.CellIndex.indexByColumnRow(
            columnIndex: i, rowIndex: headerRow),
      );
      cell.value = excel_lib.TextCellValue(compact);
      cell.cellStyle = hdrStyle;
    }
    sheet.setRowHeight(headerRow, lines == 2 ? font * 2 + 12 : 18);
  }

  static void _fitHeaderLabels(
    excel_lib.Sheet sheet,
    List<List<excel_lib.Data?>> rows,
    int maxLine,
  ) {
    final limit = rows.length < 16 ? rows.length : 16;
    for (var r = 0; r < limit; r++) {
      final row = rows[r];
      var texts = 0;
      var nums = 0;
      var chars = 0;
      for (final cell in row) {
        final value = cell?.value;
        if (value is excel_lib.TextCellValue) {
          final t = value.toString().trim();
          if (t.isEmpty) continue;
          texts++;
          chars += t.length;
        } else if (value is excel_lib.IntCellValue ||
            value is excel_lib.DoubleCellValue ||
            value is excel_lib.FormulaCellValue) {
          nums++;
        }
      }
      if (nums > 0) break;
      if (texts < 3 || chars / texts > 24) continue;
      var lines = 1;
      for (var c = 0; c < row.length; c++) {
        final data = row[c];
        final value = data?.value;
        if (value is! excel_lib.TextCellValue) continue;
        final raw = value.toString();
        if (raw.trim().isEmpty || raw.length > 36) continue;
        final compact = compactHeader(raw, maxLine: maxLine);
        if (compact.contains('\n')) lines = 2;
        final cell = sheet.cell(
          excel_lib.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r),
        );
        cell.value = excel_lib.TextCellValue(compact);
        final existing = data?.cellStyle;
        cell.cellStyle = (existing ??
                excel_lib.CellStyle(
                  bold: true,
                  horizontalAlign: excel_lib.HorizontalAlign.Center,
                ))
            .copyWith(
          textWrappingVal: excel_lib.TextWrapping.WrapText,
          verticalAlignVal: excel_lib.VerticalAlign.Center,
        );
      }
      sheet.setRowHeight(r, lines == 2 ? 34 : 18);
      break;
    }
  }

  /// A4 ngang. [pagesTall] = 0: nhiều trang dọc; 1: gom hết một trang.
  static List<int> fitSheetToA4Landscape(List<int> xlsxBytes, {int pagesTall = 0}) {
    try {
      final archive = ZipDecoder().decodeBytes(xlsxBytes);
      var changed = false;
      for (var i = 0; i < archive.files.length; i++) {
        final file = archive.files[i];
        if (!file.isFile) continue;
        final name = file.name.replaceAll('\\', '/');
        if (!name.startsWith('xl/worksheets/') || !name.endsWith('.xml')) {
          continue;
        }
        final raw = file.content;
        if (raw is! List<int>) continue;
        final xml = utf8.decode(raw);
        final patched = _injectA4Landscape(xml, pagesTall: pagesTall);
        if (patched == xml) continue;
        final data = utf8.encode(patched);
        archive.addFile(ArchiveFile(file.name, data.length, data));
        changed = true;
      }
      if (!changed) return xlsxBytes;
      return ZipEncoder().encode(archive) ?? xlsxBytes;
    } catch (_) {
      return xlsxBytes;
    }
  }

  static int _colLettersToIndex(String letters) {
    var n = 0;
    for (final code in letters.codeUnits) {
      n = n * 26 + (code - 64);
    }
    return n;
  }

  static String _colIndexToLetters(int index) {
    var n = index;
    final codes = <int>[];
    while (n > 0) {
      n--;
      codes.add(65 + (n % 26));
      n ~/= 26;
    }
    return String.fromCharCodes(codes.reversed);
  }

  static String _injectA4Landscape(String xml, {int pagesTall = 0}) {
    var out = xml.replaceAll(' bestFit="1"', '');
    out = out.replaceAll(' view="pageLayout"', '');
    if (!out.contains('<sheetPr')) {
      out = out.replaceFirstMapped(
        RegExp(r'(<worksheet\b[^>]*>)'),
        (m) => '${m[1]}<sheetPr><pageSetUpPr fitToPage="1"/></sheetPr>',
      );
    } else if (!out.contains('fitToPage')) {
      out = out.replaceFirstMapped(
        RegExp(r'<sheetPr\b([^>]*?)(/?)>'),
        (m) {
          final selfClose = m[2] == '/';
          if (selfClose) {
            return '<sheetPr${m[1]}><pageSetUpPr fitToPage="1"/></sheetPr>';
          }
          return '<sheetPr${m[1]}><pageSetUpPr fitToPage="1"/>';
        },
      );
    }
    final format = RegExp(r'<sheetFormatPr\b[^>]*/>').firstMatch(out);
    final dimAt = out.indexOf('<dimension');
    if (format != null && dimAt >= 0 && format.start < dimAt) {
      final tag = format.group(0)!;
      out = out.replaceFirst(tag, '');
      if (out.contains('</sheetViews>')) {
        out = out.replaceFirst('</sheetViews>', '</sheetViews>$tag');
      } else {
        out = out.replaceFirst('<sheetData', '$tag<sheetData');
      }
    }
    var maxRow = 1;
    var maxCol = 1;
    for (final cell in RegExp(r'\br="([A-Z]+)(\d+)"').allMatches(out)) {
      final col = _colLettersToIndex(cell.group(1)!);
      final row = int.tryParse(cell.group(2)!) ?? 1;
      if (col > maxCol) maxCol = col;
      if (row > maxRow) maxRow = row;
    }
    final dim = 'A1:${_colIndexToLetters(maxCol)}$maxRow';
    if (out.contains('<dimension')) {
      out = out.replaceFirst(
        RegExp(r'<dimension\b[^>]*/>'),
        '<dimension ref="$dim"/>',
      );
    }
    const margins =
        '<pageMargins left="0.3" right="0.3" top="0.4" bottom="0.4" header="0.2" footer="0.2"/>';
    final tall = pagesTall < 0 ? 0 : pagesTall;
    final setup =
        '<pageSetup paperSize="9" orientation="landscape" fitToWidth="1" fitToHeight="$tall"/>';
    if (out.contains('<pageMargins')) {
      out = out.replaceFirst(RegExp(r'<pageMargins\b[^>]*/>'), margins);
    } else {
      out = out.replaceFirst('</worksheet>', '$margins</worksheet>');
    }
    if (out.contains('<pageSetup')) {
      out = out.replaceFirst(RegExp(r'<pageSetup\b[^>]*/>'), setup);
    } else {
      out = out.replaceFirst(margins, '$margins$setup');
    }
    if (!out.contains('<printOptions')) {
      out = out.replaceFirst(
        margins,
        '<printOptions horizontalCentered="1"/>$margins',
      );
    }
    return out;
  }

  /// Làm tròn 1 số thập phân, ngăn cách hàng nghìn, cột đều trên A4 ngang.
  static List<int>? encodeReport(excel_lib.Excel workbook) {
    for (final name in workbook.sheets.keys.toList()) {
      try {
        polishReportSheet(workbook[name]);
      } catch (_) {}
    }
    final raw = workbook.encode();
    if (raw == null) return null;
    return fitSheetToA4Landscape(raw);
  }

  static void polishReportSheet(excel_lib.Sheet sheet) {
    final snapshot = sheet.rows;
    var cols = 0;
    for (var r = 0; r < snapshot.length; r++) {
      final row = snapshot[r];
      if (row.length > cols) cols = row.length;
      for (var c = 0; c < row.length; c++) {
        final data = row[c];
        if (data == null) continue;
        final value = data.value;
        final existing = data.cellStyle;
        if (value is excel_lib.IntCellValue) {
          _paintReportNumber(
            sheet,
            r,
            c,
            existing,
            excel_lib.NumFormat.standard_3,
          );
        } else if (value is excel_lib.DoubleCellValue) {
          final rounded = double.parse(value.value.toStringAsFixed(1));
          final whole = rounded == rounded.roundToDouble();
          sheet
              .cell(excel_lib.CellIndex.indexByColumnRow(
                  columnIndex: c, rowIndex: r))
              .value = whole
                  ? excel_lib.IntCellValue(rounded.round())
                  : excel_lib.DoubleCellValue(rounded);
          _paintReportNumber(
            sheet,
            r,
            c,
            existing,
            whole
                ? excel_lib.NumFormat.standard_3
                : excel_lib.NumFormat.custom(formatCode: '#,##0.0'),
          );
        } else if (value is excel_lib.FormulaCellValue) {
          final code = existing?.numberFormat.formatCode ?? 'General';
          if (code == 'General' || code == '0.00' || code == '0') {
            _paintReportNumber(
              sheet,
              r,
              c,
              existing,
              excel_lib.NumFormat.custom(formatCode: '#,##0.0'),
            );
          }
        }
      }
    }
    if (cols <= 0) return;
    final width = 145.0 / cols;
    final w = width < 8 ? 8.0 : width;
    final maxLine = w.floor() - 1;
    _fitHeaderLabels(sheet, snapshot, maxLine < 4 ? 4 : maxLine);
    for (var i = 0; i < cols; i++) {
      sheet.setColumnWidth(i, w);
    }
  }

  static void _paintReportNumber(
    excel_lib.Sheet sheet,
    int row,
    int col,
    excel_lib.CellStyle? existing,
    excel_lib.NumFormat format,
  ) {
    final cell = sheet.cell(
      excel_lib.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row),
    );
    cell.cellStyle = existing == null
        ? excel_lib.CellStyle(
            numberFormat: format,
            horizontalAlign: excel_lib.HorizontalAlign.Center,
            verticalAlign: excel_lib.VerticalAlign.Center,
          )
        : existing.copyWith(numberFormat: format);
  }
}
