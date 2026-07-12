/// Web-only save handle — no-op on mobile/desktop.
class WebExcelSaveHandle {
  const WebExcelSaveHandle._();
}

Future<WebExcelSaveHandle?> beginWebExcelSave(
  String filename,
  String mimeType,
) async =>
    null;

Future<void> completeWebExcelSave(
  WebExcelSaveHandle handle,
  List<int> bytes, {
  required String mimeType,
}) async {}
