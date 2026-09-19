import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../widgets/notification_overlay.dart';
import 'file_saver.dart' as file_saver;
import 'report_screen_helpers.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

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
  }) {
    return ClientExcelExport.export(
      context: context,
      title: title,
      sheetName: sheetName,
      filePrefix: filePrefix,
      headers: headers,
      rows: rows,
      periodLabel: periodLabel,
      filterLabel: filterLabel,
      summaryLines: summaryLines,
    );
  }

  /// Tải file Excel từ API (bytes) rồi lưu máy / trình duyệt.
  static Future<bool> serverExcel({
    required BuildContext context,
    required Future<Map<String, dynamic>> Function() fetch,
    required String filePrefix,
    String successMessage = 'Đã xuất Excel',
  }) async {
    final res = await fetch();
    if (!context.mounted) return false;
    if (res['isSuccess'] != true || res['data'] == null) {
      NotificationOverlayManager().showError(
        title: tr('Xuất file'),
        message: tr('${res['message'] ?? 'Không xuất được Excel'}'),
      );
      return false;
    }
    final bytes = Uint8List.fromList(List<int>.from(res['data'] as List));
    final name =
        '${filePrefix}_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.xlsx';
    await file_saver.saveFileBytes(
      bytes,
      name,
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    );
    if (!context.mounted) return true;
    NotificationOverlayManager().showSuccess(
      title: tr('Xuất file'),
      message: tr(successMessage),
    );
    return true;
  }

  static Future<bool> png({
    required BuildContext context,
    required GlobalKey key,
    required String filePrefix,
    double pixelRatio = 2.5,
  }) {
    return ClientPngExport.capture(
      context: context,
      key: key,
      filePrefix: filePrefix,
      pixelRatio: pixelRatio,
    );
  }
}
