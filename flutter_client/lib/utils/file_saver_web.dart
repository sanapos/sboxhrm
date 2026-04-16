import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;

/// Download a file from raw bytes on Web (Blob + AnchorElement).
Future<void> saveFileBytes(List<int> bytes, String filename, String mimeType) async {
  final uint8List = Uint8List.fromList(bytes);
  final jsArray = uint8List.toJS;
  final blob = web.Blob([jsArray].toJS, web.BlobPropertyBag(type: mimeType));
  final url = web.URL.createObjectURL(blob);
  final anchor = web.document.createElement('a') as web.HTMLAnchorElement
    ..href = url
    ..download = filename;
  anchor.style.display = 'none';
  web.document.body!.appendChild(anchor);
  anchor.click();
  anchor.remove();
  web.URL.revokeObjectURL(url);
}

/// Download a file from a data-URL string on Web.
Future<void> saveDataUrl(String dataUrl, String filename) async {
  final anchor = web.document.createElement('a') as web.HTMLAnchorElement
    ..href = dataUrl
    ..download = filename;
  anchor.style.display = 'none';
  web.document.body!.appendChild(anchor);
  anchor.click();
  anchor.remove();
}
