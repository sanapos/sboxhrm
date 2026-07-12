import 'dart:js_interop';
import 'dart:js_util' as js_util;
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'excel_bytes_utils.dart';
import 'web_excel_save_stub.dart';

/// Handle from [beginWebExcelSave] — write bytes after async fetch completes.
class WebExcelSaveHandle {
  final JSObject fileHandle;
  const WebExcelSaveHandle(this.fileHandle);
}

Future<WebExcelSaveHandle?> beginWebExcelSave(
  String filename,
  String mimeType,
) async {
  if (!js_util.hasProperty(web.window, 'showSaveFilePicker')) return null;
  try {
    final safeName = normalizeExportFileName(filename);
    final ext = safeName.toLowerCase().endsWith('.xls') ? '.xls' : '.xlsx';
    final options = js_util.jsify({
      'suggestedName': safeName,
      'types': [
        {
          'description': 'Excel Workbook',
          'accept': {
            mimeType: [ext],
          },
        },
      ],
    });
    final handle = await js_util.promiseToFuture<Object>(
      js_util.callMethod(web.window, 'showSaveFilePicker', [options]),
    );
    return WebExcelSaveHandle(handle as JSObject);
  } catch (_) {
    // User cancelled or browser blocked the picker.
    return null;
  }
}

Future<void> completeWebExcelSave(
  WebExcelSaveHandle handle,
  List<int> bytes, {
  required String mimeType,
}) async {
  final writable = await js_util.promiseToFuture<Object>(
    js_util.callMethod(handle.fileHandle, 'createWritable', []),
  );
  final blob = web.Blob(
    [Uint8List.fromList(bytes).toJS].toJS,
    web.BlobPropertyBag(type: mimeType),
  );
  await js_util.promiseToFuture(
    js_util.callMethod(writable, 'write', [blob]),
  );
  await js_util.promiseToFuture(
    js_util.callMethod(writable, 'close', []),
  );
}
