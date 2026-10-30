import 'package:excel/excel.dart' as excel_lib;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

import '../utils/api_datetime.dart';
import '../utils/excel_report_builder.dart';
import '../utils/file_saver.dart' as file_saver;
import '../utils/report_screen_helpers.dart' show ClientPngExport;
import '../widgets/notification_overlay.dart';
import '../widgets/report_column_picker.dart';

/// Cột file Excel danh sách phiếu lương (chọn / sắp xếp trước khi xuất).
const payslipExcelColumnDefs = <ReportColumnDef>[
  ReportColumnDef('stt', 'STT', locked: true),
  ReportColumnDef('period', 'Kỳ lương'),
  ReportColumnDef('periodRange', 'Từ ngày – đến ngày', defaultVisible: false),
  ReportColumnDef('code', 'Mã nhân viên'),
  ReportColumnDef('name', 'Tên nhân viên'),
  ReportColumnDef('dept', 'Phòng ban'),
  ReportColumnDef('workUnits', 'Số công'),
  ReportColumnDef('otUnits', 'Công tăng ca', defaultVisible: false),
  ReportColumnDef('baseSalary', 'Lương cơ bản'),
  ReportColumnDef('overtimePay', 'Lương tăng ca'),
  ReportColumnDef('holidayPay', 'Lương ngày lễ', defaultVisible: false),
  ReportColumnDef('nightShiftPay', 'Lương ca đêm', defaultVisible: false),
  ReportColumnDef('travelSalary', 'Lương đi đường', defaultVisible: false),
  ReportColumnDef('allowances', 'Phụ cấp'),
  ReportColumnDef('bonus', 'Thưởng'),
  ReportColumnDef('gross', 'Tổng lương'),
  ReportColumnDef('social', 'BHXH'),
  ReportColumnDef('health', 'BHYT'),
  ReportColumnDef('unemployment', 'BHTN'),
  ReportColumnDef('tax', 'Thuế TNCN'),
  ReportColumnDef('deductions', 'Khấu trừ khác'),
  ReportColumnDef('net', 'Thực lĩnh'),
  ReportColumnDef('status', 'Trạng thái'),
  ReportColumnDef('payment', 'Thanh toán'),
  ReportColumnDef('paid', 'Đã trả'),
  ReportColumnDef('remaining', 'Còn lại'),
  ReportColumnDef('paidDate', 'Ngày trả', defaultVisible: false),
  ReportColumnDef('cashCode', 'Mã phiếu chi', defaultVisible: false),
  ReportColumnDef('notes', 'Ghi chú', defaultVisible: false),
];

const _prefKey = 'payslip_excel_cols_v1';

/// Cột tiền (cộng ở dòng TỔNG CỘNG) → khóa trường trong phiếu lương.
const _moneyFields = <String, String>{
  'baseSalary': 'baseSalary',
  'overtimePay': 'overtimePay',
  'holidayPay': 'holidayPay',
  'nightShiftPay': 'nightShiftPay',
  'travelSalary': 'travelSalary',
  'allowances': 'allowances',
  'bonus': 'bonus',
  'gross': 'grossSalary',
  'social': 'socialInsurance',
  'health': 'healthInsurance',
  'unemployment': 'unemploymentInsurance',
  'tax': 'tax',
  'deductions': 'deductions',
  'net': 'netSalary',
  'paid': 'paidAmount',
  'remaining': 'remainingAmount',
};

const _unitFields = <String, String>{
  'workUnits': 'regularWorkUnits',
  'otUnits': 'overtimeUnits',
};

/// Ảnh PNG danh sách phiếu lương — bảng gọn (ảnh không đủ rộng cho mọi cột như Excel).
Future<void> exportPayslipsToPng(
  BuildContext context,
  List<Map<String, dynamic>> payslips, {
  required String Function(Map<String, dynamic>) statusLabel,
  required bool Function(Map<String, dynamic>) isPaid,
  String? filterDescription,
}) async {
  num n(Object? v) => v is num ? v : num.tryParse('${v ?? ''}') ?? 0;
  final rows = <List<dynamic>>[];
  num gross = 0, deduct = 0, net = 0, remaining = 0;
  for (var i = 0; i < payslips.length; i++) {
    final p = payslips[i];
    final m = (p['month'] as num?)?.toInt();
    final y = (p['year'] as num?)?.toInt();
    final d = n(p['socialInsurance']) + n(p['healthInsurance']) + n(p['unemploymentInsurance']) +
        n(p['tax']) + n(p['deductions']);
    gross += n(p['grossSalary']);
    deduct += d;
    net += n(p['netSalary']);
    remaining += n(p['remainingAmount']);
    rows.add([
      i + 1,
      m != null && y != null ? 'T${m.toString().padLeft(2, '0')}/$y' : '',
      p['employeeCode']?.toString() ?? '',
      p['employeeName']?.toString() ?? '',
      p['department']?.toString() ?? '',
      n(p['regularWorkUnits']),
      n(p['grossSalary']),
      d,
      n(p['netSalary']),
      statusLabel(p),
      p['paymentStatus']?.toString() ?? (isPaid(p) ? 'Đã thanh toán' : 'Chưa thanh toán'),
    ]);
  }
  final money = NumberFormat('#,##0', 'vi_VN');
  await ClientPngExport.table(
    context: context,
    title: 'DANH SÁCH PHIẾU LƯƠNG',
    filePrefix: 'Phieu_luong',
    headers: const [
      'STT', 'Kỳ lương', 'Mã NV', 'Tên nhân viên', 'Phòng ban', 'Số công',
      'Tổng lương', 'Khấu trừ', 'Thực lĩnh', 'Trạng thái', 'Thanh toán',
    ],
    rows: rows,
    periodLabel: filterDescription == null || filterDescription.isEmpty ? null : 'Bộ lọc: $filterDescription',
    summaryLines: [
      '${payslips.length} phiếu · Tổng lương ${money.format(gross)} đ · Khấu trừ ${money.format(deduct)} đ',
      'Thực lĩnh ${money.format(net)} đ · Còn phải trả ${money.format(remaining)} đ',
    ],
  );
}

/// Chọn cột rồi xuất [payslips] (đã lọc, đúng thứ tự đang hiển thị) ra Excel.
Future<void> exportPayslipsToExcel(
  BuildContext context,
  List<Map<String, dynamic>> payslips, {
  required String Function(Map<String, dynamic>) statusLabel,
  required bool Function(Map<String, dynamic>) isPaid,
  String? filterDescription,
}) async {
  if (payslips.isEmpty) {
    NotificationOverlayManager()
        .showWarning(title: 'Không có dữ liệu', message: tr('Không có phiếu lương để xuất'));
    return;
  }
  final saved = await ReportColumnPrefs.load(_prefKey, payslipExcelColumnDefs);
  if (!context.mounted) return;
  final pick = await showReportColumnPicker(
    context,
    title: 'Xuất Excel — chọn cột',
    defs: payslipExcelColumnDefs,
    initial: saved,
    confirmLabel: 'Xuất Excel',
    showRemember: true,
  );
  if (pick == null) return;
  if (pick.remember) await ReportColumnPrefs.save(_prefKey, pick.layout);

  try {
    final labels = {for (final d in payslipExcelColumnDefs) d.key: d.label};
    final cols = pick.layout.visibleOrder;
    final lastCol = cols.length - 1;
    final wb = ExcelReportBuilder.createWorkbook(sheetName: 'Phiếu lương');
    final sheet = wb['Phiếu lương'];

    num n(Object? v) => v is num ? v : num.tryParse('${v ?? ''}') ?? 0;
    final money = excel_lib.NumFormat.custom(formatCode: '#,##0');
    final units = excel_lib.NumFormat.custom(formatCode: '#,##0.##');
    excel_lib.CellStyle style({bool left = false, bool bold = false, excel_lib.NumFormat? fmt, String? bg}) =>
        excel_lib.CellStyle(
          bold: bold,
          horizontalAlign: left ? excel_lib.HorizontalAlign.Left : excel_lib.HorizontalAlign.Center,
          verticalAlign: excel_lib.VerticalAlign.Center,
          numberFormat: fmt ?? excel_lib.NumFormat.standard_0,
          backgroundColorHex:
              bg != null ? excel_lib.ExcelColor.fromHexString(bg) : excel_lib.ExcelColor.none,
        );
    void merged(int row, String text, excel_lib.CellStyle st) {
      final cell = sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row));
      cell.value = excel_lib.TextCellValue(text);
      cell.cellStyle = st;
      if (lastCol > 0) {
        sheet.merge(excel_lib.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row),
            excel_lib.CellIndex.indexByColumnRow(columnIndex: lastCol, rowIndex: row));
      }
    }

    void set(int row, int col, excel_lib.CellValue v, excel_lib.CellStyle st) {
      final cell = sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row));
      cell.value = v;
      cell.cellStyle = st;
    }

    String colRef(int c, int r) {
      var x = c + 1;
      final b = StringBuffer();
      while (x > 0) {
        b.write(String.fromCharCode(65 + (x - 1) % 26));
        x = (x - 1) ~/ 26;
      }
      return '${b.toString().split('').reversed.join()}${r + 1}';
    }

    var row = 0;
    merged(row++, tr('DANH SÁCH PHIẾU LƯƠNG'), ExcelReportBuilder.titleStyle());
    merged(
        row++,
        tr('Xuất lúc: ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}  |  ${payslips.length} phiếu'),
        style());
    if (filterDescription != null && filterDescription.isNotEmpty) {
      merged(row++, tr('Bộ lọc: $filterDescription'), style());
    }
    row++;

    ExcelReportBuilder.applyHeaderRow(sheet, row, [for (final k in cols) labels[k]!],
        style: ExcelReportBuilder.headerStyle());
    row++;

    final firstDataRow = row;
    for (var i = 0; i < payslips.length; i++) {
      final p = payslips[i];
      for (var c = 0; c < cols.length; c++) {
        final k = cols[c];
        if (_moneyFields[k] case final f?) {
          set(row, c, excel_lib.DoubleCellValue(n(p[f]).toDouble()), style(fmt: money));
          continue;
        }
        if (_unitFields[k] case final f?) {
          set(row, c, excel_lib.DoubleCellValue(n(p[f]).toDouble()), style(fmt: units));
          continue;
        }
        final m = (p['month'] as num?)?.toInt();
        final y = (p['year'] as num?)?.toInt();
        final (String text, bool left) = switch (k) {
          'stt' => ('${i + 1}', false),
          'period' => (m != null && y != null ? 'T${m.toString().padLeft(2, '0')}/$y' : '', false),
          'periodRange' => (
              '${formatApiDateTime(p['periodStart'], pattern: 'dd/MM/yyyy')} – '
                  '${formatApiDateTime(p['periodEnd'], pattern: 'dd/MM/yyyy')}',
              false
            ),
          'code' => (p['employeeCode']?.toString() ?? '', false),
          'name' => (p['employeeName']?.toString() ?? '', true),
          'dept' => (p['department']?.toString() ?? '', true),
          'status' => (statusLabel(p), false),
          'payment' => (
              p['paymentStatus']?.toString() ?? (isPaid(p) ? 'Đã thanh toán' : 'Chưa thanh toán'),
              false
            ),
          'paidDate' => (
              p['paidDate'] == null ? '' : formatApiDateTime(p['paidDate'], pattern: 'dd/MM/yyyy'),
              false
            ),
          'cashCode' => (p['cashTransactionCode']?.toString() ?? '', false),
          _ => (p['notes']?.toString() ?? '', true),
        };
        set(row, c, k == 'stt' ? excel_lib.IntCellValue(i + 1) : excel_lib.TextCellValue(text),
            style(left: left));
      }
      row++;
    }
    final lastDataRow = row - 1;

    const totalBg = '#EFF6FF';
    for (var c = 0; c < cols.length; c++) {
      final k = cols[c];
      final sum = _moneyFields.containsKey(k) || _unitFields.containsKey(k);
      set(
        row,
        c,
        sum
            ? excel_lib.FormulaCellValue('SUM(${colRef(c, firstDataRow)}:${colRef(c, lastDataRow)})')
            : excel_lib.TextCellValue(k == 'stt' ? 'TỔNG CỘNG' : ''),
        style(
            bold: true,
            bg: totalBg,
            fmt: _moneyFields.containsKey(k) ? money : (_unitFields.containsKey(k) ? units : null)),
      );
    }

    for (var c = 0; c < cols.length; c++) {
      sheet.setColumnWidth(
          c,
          switch (cols[c]) {
            'stt' => 12,
            'name' => 24,
            'dept' => 18,
            'periodRange' => 24,
            'notes' => 28,
            'payment' || 'status' => 15,
            _ => 13,
          });
    }

    final bytes = ExcelReportBuilder.encodeReport(wb);
    if (bytes == null) return;
    final fn = 'Danh_sach_phieu_luong_${DateFormat('ddMMyyyy_HHmm').format(DateTime.now())}.xlsx';
    await file_saver.saveAndOpenFileBytes(
        bytes, fn, 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
    NotificationOverlayManager().showSuccess(
        title: 'Xuất Excel', message: tr('Đã lưu ${payslips.length} phiếu lương vào Tải về/SBOX HRM: $fn'));
  } catch (e) {
    NotificationOverlayManager().showError(title: 'Lỗi', message: tr('Không thể xuất Excel: $e'));
  }
}
