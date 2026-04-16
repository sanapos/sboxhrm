// ignore: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:html' as html;

/// Create an HTML canvas, let [draw] paint on its 2D context,
/// then return the resulting PNG as a data-URL.
String? renderToPngDataUrl({
  required int width,
  required int height,
  required void Function(dynamic ctx) draw,
}) {
  final canvas = html.CanvasElement(width: width, height: height);
  draw(canvas.context2D);
  return canvas.toDataUrl('image/png');
}

/// On web, not needed since renderToPngDataUrl works.
/// Provided for API compatibility.
Future<List<int>?> renderToPngBytes({
  required int width,
  required int height,
  required void Function(dynamic ctx) draw,
}) async {
  return null;
}
