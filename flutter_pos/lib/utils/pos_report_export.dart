import 'dart:ui' as ui;

import 'package:excel/excel.dart' as excel_lib;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../l10n/app_tr.dart';
import '../providers/auth_provider.dart';
import '../widgets/notification_overlay.dart';
import 'excel_bytes_utils.dart';
import 'excel_report_builder.dart';
import 'file_saver.dart' as file_saver;

class PosReportExport {
  static Future<bool> excel({
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
        title: 'Thông báo',
        message: tr('Không có dữ liệu để xuất'),
      );
      return false;
    }
    try {
      final fn = normalizeExportFileName(
        '${filePrefix}_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.xlsx',
      );
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
        ExcelReportBuilder.writeRow(sh, rowIdx++, row.map(_cell).toList());
      }
      final bytes = wb.encode();
      if (bytes == null || !isValidXlsxBytes(bytes)) {
        NotificationOverlayManager().showError(
          title: 'Lỗi',
          message: tr('Không tạo được file Excel hợp lệ.'),
        );
        return false;
      }
      await file_saver.saveAndOpenFileBytes(
        bytes,
        fn,
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      );
      if (context.mounted) {
        NotificationOverlayManager()
            .showSuccess(title: 'Xuất Excel', message: tr('Đã xuất $fn'));
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

  static Future<bool> png({
    required BuildContext context,
    required GlobalKey key,
    required String filePrefix,
    double pixelRatio = 2.5,
  }) async {
    try {
      final boundary =
          key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        NotificationOverlayManager().showWarning(
          title: 'Xuất PNG',
          message: tr('Không tìm thấy nội dung báo cáo để chụp'),
        );
        return false;
      }
      final image = await boundary.toImage(pixelRatio: pixelRatio);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        NotificationOverlayManager()
            .showError(title: 'Xuất PNG', message: tr('Không thể tạo ảnh'));
        return false;
      }
      final fileName = normalizeExportFileName(
        '${filePrefix}_${DateFormat('ddMMyyyy_HHmm').format(DateTime.now())}.png',
      );
      await file_saver.saveAndOpenFileBytes(
        byteData.buffer.asUint8List(),
        fileName,
        'image/png',
      );
      if (context.mounted) {
        NotificationOverlayManager()
            .showSuccess(title: 'Xuất PNG', message: tr('Đã xuất $fileName'));
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

  static excel_lib.CellValue? _cell(dynamic v) {
    if (v == null) return null;
    if (v is int) return excel_lib.IntCellValue(v);
    if (v is double) return excel_lib.DoubleCellValue(v);
    if (v is num) return excel_lib.DoubleCellValue(v.toDouble());
    if (v is bool) return excel_lib.BoolCellValue(v);
    return excel_lib.TextCellValue(v.toString());
  }
}
