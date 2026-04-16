import 'dart:ui' as ui;
import 'package:flutter/painting.dart';

/// Mobile implementation using Flutter's dart:ui Canvas.
/// Provides an adapter that emulates HTML Canvas2D API methods.
String? renderToPngDataUrl({
  required int width,
  required int height,
  required void Function(dynamic ctx) draw,
}) {
  // We can't do synchronous image encoding in dart:ui,
  // so return null here. Use the async version instead.
  return null;
}

/// Async version for mobile - renders to PNG bytes directly.
Future<List<int>?> renderToPngBytes({
  required int width,
  required int height,
  required void Function(dynamic ctx) draw,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder, ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()));

  final adapter = _MobileCanvasAdapter(canvas);
  draw(adapter);

  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  picture.dispose();
  image.dispose();

  if (byteData == null) return null;
  return byteData.buffer.asUint8List();
}

/// Adapter that translates HTML Canvas2D API calls to Flutter Canvas calls.
class _MobileCanvasAdapter {
  final ui.Canvas _canvas;

  String _fillStyle = '#000000';
  String _strokeStyle = '#000000';
  double _lineWidth = 1.0;
  String _font = '12px Arial';
  String _textAlign = 'left';

  // Path state
  final List<ui.Offset> _pathPoints = [];

  _MobileCanvasAdapter(this._canvas);

  // ignore: unused_element
  set fillStyle(dynamic value) => _fillStyle = value.toString();
  set strokeStyle(dynamic value) => _strokeStyle = value.toString();
  set lineWidth(dynamic value) => _lineWidth = (value is num) ? value.toDouble() : 1.0;
  set font(dynamic value) => _font = value.toString();
  set textAlign(dynamic value) => _textAlign = value.toString();

  void fillRect(dynamic x, dynamic y, dynamic w, dynamic h) {
    final paint = ui.Paint()
      ..color = _parseColor(_fillStyle)
      ..style = ui.PaintingStyle.fill;
    _canvas.drawRect(
      ui.Rect.fromLTWH(_toDouble(x), _toDouble(y), _toDouble(w), _toDouble(h)),
      paint,
    );
  }

  void strokeRect(dynamic x, dynamic y, dynamic w, dynamic h) {
    final paint = ui.Paint()
      ..color = _parseColor(_strokeStyle)
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = _lineWidth;
    _canvas.drawRect(
      ui.Rect.fromLTWH(_toDouble(x), _toDouble(y), _toDouble(w), _toDouble(h)),
      paint,
    );
  }

  void fillText(dynamic text, dynamic x, dynamic y) {
    final fontSize = _parseFontSize(_font);
    final isBold = _font.contains('bold');
    final tp = TextPainter(
      text: TextSpan(
        text: text.toString(),
        style: TextStyle(
          color: _parseColor(_fillStyle),
          fontSize: fontSize,
          fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();

    double dx = _toDouble(x);
    if (_textAlign == 'center') {
      dx -= tp.width / 2;
    } else if (_textAlign == 'right') {
      dx -= tp.width;
    }
    // HTML fillText y is baseline; Flutter paints from top. Adjust.
    final dy = _toDouble(y) - fontSize * 0.8;
    tp.paint(_canvas, ui.Offset(dx, dy));
    tp.dispose();
  }

  void beginPath() => _pathPoints.clear();

  void moveTo(dynamic x, dynamic y) {
    _pathPoints.clear();
    _pathPoints.add(ui.Offset(_toDouble(x), _toDouble(y)));
  }

  void lineTo(dynamic x, dynamic y) {
    _pathPoints.add(ui.Offset(_toDouble(x), _toDouble(y)));
  }

  void stroke() {
    if (_pathPoints.length < 2) return;
    final paint = ui.Paint()
      ..color = _parseColor(_strokeStyle)
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = _lineWidth;
    for (int i = 0; i < _pathPoints.length - 1; i++) {
      _canvas.drawLine(_pathPoints[i], _pathPoints[i + 1], paint);
    }
  }

  // Helpers
  static double _toDouble(dynamic v) => (v is num) ? v.toDouble() : 0.0;

  static double _parseFontSize(String font) {
    final match = RegExp(r'(\d+(?:\.\d+)?)px').firstMatch(font);
    return match != null ? double.tryParse(match.group(1)!) ?? 12.0 : 12.0;
  }

  static ui.Color _parseColor(String color) {
    if (color.startsWith('#')) {
      final hex = color.substring(1);
      if (hex.length == 6) return ui.Color(int.parse('FF$hex', radix: 16));
      if (hex.length == 8) return ui.Color(int.parse(hex, radix: 16));
    }
    return const ui.Color(0xFF000000);
  }
}
