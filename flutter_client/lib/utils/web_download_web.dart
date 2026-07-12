import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'excel_bytes_utils.dart';

Future<void> downloadPngBytes(List<int> bytes, String filename) async {
  final safeName = normalizeSaveFileName(filename, mimeType: 'image/png');
  final uint8List = Uint8List.fromList(bytes);

  if (uint8List.length <= 20 * 1024 * 1024) {
    try {
      final b64 = base64Encode(uint8List);
      final dataUrl = 'data:image/png;base64,$b64';
      final anchor = web.HTMLAnchorElement()
        ..href = dataUrl
        ..download = safeName
        ..style.display = 'none';
      web.document.body!.appendChild(anchor);
      anchor.click();
      await Future<void>.delayed(const Duration(milliseconds: 600));
      anchor.remove();
      return;
    } catch (_) {}
  }

  final blob = web.Blob(
    [uint8List.toJS].toJS,
    web.BlobPropertyBag(type: 'image/png'),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = safeName
    ..style.display = 'none';
  web.document.body!.appendChild(anchor);
  anchor.click();
  await Future<void>.delayed(const Duration(seconds: 5));
  anchor.remove();
  web.URL.revokeObjectURL(url);
}
