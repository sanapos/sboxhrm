import 'dart:js_interop';
import 'dart:js_interop_unsafe';
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
  final window = web.window as JSObject;
  if (window.getProperty('showSaveFilePicker'.toJS) == null) return null;
  try {
    final safeName = normalizeExportFileName(filename);
    final ext = safeName.toLowerCase().endsWith('.xls') ? '.xls' : '.xlsx';
    final options = {
      'suggestedName': safeName,
      'types': [
        {
          'description': 'Excel Workbook',
          'accept': {
            mimeType: [ext],
          },
        },
      ],
    }.jsify();
    final handlePromise =
        window.callMethod('showSaveFilePicker'.toJS, options) as JSPromise;
    final handle = await handlePromise.toDart;
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
  final writablePromise = handle.fileHandle
      .callMethod('createWritable'.toJS) as JSPromise;
  final writable = await writablePromise.toDart as JSObject;
  final blob = web.Blob(
    [Uint8List.fromList(bytes).toJS].toJS,
    web.BlobPropertyBag(type: mimeType),
  );
  await (writable.callMethod('write'.toJS, blob) as JSPromise).toDart;
  await (writable.callMethod('close'.toJS) as JSPromise).toDart;
}
