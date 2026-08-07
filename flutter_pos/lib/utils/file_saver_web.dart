import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'excel_bytes_utils.dart';

/// Max size for data-URL download (Chrome handles this reliably without user gesture).
const _kDataUrlMaxBytes = 20 * 1024 * 1024;

/// Download a file from raw bytes on Web.
Future<String?> saveFileBytes(
  List<int> bytes,
  String filename,
  String mimeType, {
  String? category,
  String? sourceModule,
}) async {
  final safeName = normalizeSaveFileName(filename, mimeType: mimeType);
  final uint8List = Uint8List.fromList(bytes);

  if (uint8List.length <= _kDataUrlMaxBytes) {
    try {
      return await _saveViaDataUrl(uint8List, safeName, mimeType);
    } catch (_) {
      // Fall through to blob strategies.
    }
  }

  if (_tryMsSaveOrOpenBlob(uint8List, safeName, mimeType)) {
    return safeName;
  }

  return _saveViaBlob(uint8List, safeName, mimeType);
}

bool _tryMsSaveOrOpenBlob(Uint8List bytes, String safeName, String mimeType) {
  try {
    final navigator = web.window.navigator as JSObject;
    if (navigator.getProperty('msSaveOrOpenBlob'.toJS) == null) return false;
    final blob = web.Blob(
      [bytes.toJS].toJS,
      web.BlobPropertyBag(type: mimeType),
    );
    navigator.callMethod('msSaveOrOpenBlob'.toJS, blob, safeName.toJS);
    return true;
  } catch (_) {
    return false;
  }
}

Future<String?> _saveViaDataUrl(
  Uint8List bytes,
  String safeName,
  String mimeType,
) async {
  final b64 = base64Encode(bytes);
  final dataUrl = 'data:$mimeType;base64,$b64';
  final anchor = web.HTMLAnchorElement()
    ..href = dataUrl
    ..download = safeName
    ..style.display = 'none';
  web.document.body!.appendChild(anchor);
  anchor.click();
  await Future<void>.delayed(const Duration(milliseconds: 600));
  anchor.remove();
  return safeName;
}

Future<String?> _saveViaBlob(
  Uint8List bytes,
  String safeName,
  String mimeType,
) async {
  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: mimeType),
  );
  final url = web.URL.createObjectURL(blob);

  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = safeName
    ..style.display = 'none';
  anchor.setAttribute('download', safeName);

  web.document.body!.appendChild(anchor);
  anchor.click();

  // Revoke too early → Chrome saves blob UUID without extension.
  await Future<void>.delayed(const Duration(seconds: 5));
  anchor.remove();
  web.URL.revokeObjectURL(url);
  return safeName;
}

/// Download a file from a data-URL string on Web.
Future<void> saveDataUrl(String dataUrl, String filename) async {
  String? mime;
  if (dataUrl.startsWith('data:')) {
    final semi = dataUrl.indexOf(';');
    if (semi > 5) mime = dataUrl.substring(5, semi);
  }
  final safeName = normalizeSaveFileName(
    filename,
    mimeType: mime,
    defaultExtension: '.png',
  );
  final anchor = web.HTMLAnchorElement()
    ..href = dataUrl
    ..download = safeName
    ..style.display = 'none';
  web.document.body!.appendChild(anchor);
  anchor.click();
  await Future<void>.delayed(const Duration(milliseconds: 600));
  anchor.remove();
}

/// On Web, open = download (same as save).
Future<void> saveAndOpenFileBytes(
    List<int> bytes, String filename, String mimeType) async {
  await saveFileBytes(bytes, filename, mimeType);
}

/// On Web, open = download (same as save).
Future<void> saveAndOpenDataUrl(String dataUrl, String filename) async {
  await saveDataUrl(dataUrl, filename);
}

/// Mở PDF trong tab mới (xem trước in tem trên web).
Future<void> openPdfInNewTab(List<int> bytes, String filename) async {
  final uint8List = Uint8List.fromList(bytes);
  final blob = web.Blob(
    [uint8List.toJS].toJS,
    web.BlobPropertyBag(type: 'application/pdf'),
  );
  final url = web.URL.createObjectURL(blob);
  web.window.open(url, '_blank');
  await Future<void>.delayed(const Duration(milliseconds: 1200));
  web.URL.revokeObjectURL(url);
}
