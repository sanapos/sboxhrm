import 'package:flutter/material.dart';

import 'report_screen_helpers.dart';

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
