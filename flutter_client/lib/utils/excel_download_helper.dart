import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'excel_bytes_utils.dart';
import 'file_saver.dart' as file_saver;
import 'web_excel_save.dart';

/// Shared Excel download flow for web + mobile.
///
/// On web, call [prepareSave] at the start of a user click handler (before any
/// await to the API) so Chrome keeps user activation for the save-file picker.
class ExcelDownloadHelper {
  ExcelDownloadHelper();

  static const excelMime =
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

  WebExcelSaveHandle? _handle;

  Future<void> prepareSave(String filename) async {
    if (!kIsWeb) return;
    _handle = await beginWebExcelSave(filename, excelMime);
  }

  Future<void> saveBytes(List<int> bytes, String filename) async {
    final safeName = normalizeExportFileName(filename);
    final data = Uint8List.fromList(bytes);
    if (_handle != null) {
      await completeWebExcelSave(
        _handle!,
        data,
        mimeType: excelMime,
      );
      _handle = null;
      return;
    }
    await file_saver.saveFileBytes(data, safeName, excelMime);
  }

  /// Fetch Excel from API then save — opens save picker first on web when possible.
  Future<Map<String, dynamic>> runServerExport({
    required Future<Map<String, dynamic>> Function() fetch,
    required String filename,
  }) async {
    await prepareSave(filename);
    final result = await fetch();
    if (result['isSuccess'] == true && result['data'] != null) {
      await saveBytes(List<int>.from(result['data']), filename);
    }
    return result;
  }

  /// One-shot helper when no early prepare is needed (client-side encode).
  static Future<void> saveExcelBytes(List<int> bytes, String filename) async {
    final helper = ExcelDownloadHelper();
    await helper.prepareSave(filename);
    await helper.saveBytes(bytes, filename);
  }
}
