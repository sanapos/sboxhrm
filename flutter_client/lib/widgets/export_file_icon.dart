import 'package:flutter/material.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

/// Loại tệp xuất — icon tệp quen thuộc thay cho «mũi tên tải» / «khung ảnh» xám khó phân biệt.
enum ExportFileKind { excel, png }

/// Đoán loại xuất từ nhãn nút («Xuất Excel», «Xuất PNG», «Xuất ảnh PNG»…); null = không phải nút xuất.
ExportFileKind? exportFileKindForLabel(String label) {
  final l = label.toLowerCase();
  if (!l.contains('xuất') && !l.contains('export')) return null;
  if (l.contains('excel') || l.contains('xlsx')) return ExportFileKind.excel;
  if (l.contains('png') || l.contains('xuất ảnh')) return ExportFileKind.png;
  return null;
}

/// Chữ ngắn đi kèm icon trên màn rộng.
String exportFileShortLabel(ExportFileKind kind) =>
    kind == ExportFileKind.excel ? 'Excel' : 'Ảnh PNG';

/// Icon tệp gấp góc: Excel = ô xanh lá chữ «X», PNG = hình ảnh + dải «PNG». Tự vẽ (không dùng logo hãng).
class ExportFileIcon extends StatelessWidget {
  const ExportFileIcon(this.kind, {super.key, this.size = 22, this.enabled = true});

  final ExportFileKind kind;

  /// Chiều cao icon; rộng = 7/8 cao (tỉ lệ tờ giấy).
  final double size;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final icon = CustomPaint(
      size: Size(size * 28 / 32, size),
      painter: _ExportFilePainter(kind),
    );
    return enabled ? icon : Opacity(opacity: 0.4, child: icon);
  }
}

class _ExportFilePainter extends CustomPainter {
  _ExportFilePainter(this.kind);

  final ExportFileKind kind;

  static const _excel = Color(0xFF1D6F42);
  static const _excelFold = Color(0xFFD3EAD9);
  static const _png = Color(0xFF185FA5);
  static const _pngFold = Color(0xFFD6E7F8);
  static const _pngSky = Color(0xFF378ADD);
  static const _sun = Color(0xFFEF9F27);

  @override
  void paint(Canvas canvas, Size size) {
    // Vẽ trên lưới 28×32 rồi co giãn.
    canvas.save();
    canvas.scale(size.width / 28, size.height / 32);
    final main = kind == ExportFileKind.excel ? _excel : _png;
    final fold = kind == ExportFileKind.excel ? _excelFold : _pngFold;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..color = main
      ..strokeJoin = StrokeJoin.round;

    final page = Path()
      ..moveTo(4, 1)
      ..lineTo(18, 1)
      ..lineTo(25, 8)
      ..lineTo(25, 29)
      ..arcToPoint(const Offset(23, 31), radius: const Radius.circular(2))
      ..lineTo(4, 31)
      ..arcToPoint(const Offset(2, 29), radius: const Radius.circular(2))
      ..lineTo(2, 3)
      ..arcToPoint(const Offset(4, 1), radius: const Radius.circular(2))
      ..close();
    canvas.drawPath(page, Paint()..color = Colors.white);
    canvas.drawPath(page, stroke);

    final corner = Path()
      ..moveTo(18, 1)
      ..lineTo(18, 6)
      ..arcToPoint(const Offset(20, 8), radius: const Radius.circular(2), clockwise: false)
      ..lineTo(25, 8);
    canvas.drawPath(corner, Paint()..color = fold);
    canvas.drawPath(corner, stroke);

    final band = Paint()..color = main;
    if (kind == ExportFileKind.excel) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(const Rect.fromLTWH(0, 14, 18, 13), const Radius.circular(2)),
        band,
      );
      final x = Paint()
        ..color = Colors.white
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(const Offset(5, 17.5), const Offset(12, 24.5), x);
      canvas.drawLine(const Offset(12, 17.5), const Offset(5, 24.5), x);
    } else {
      canvas.drawCircle(const Offset(9, 8), 2, Paint()..color = _sun);
      final hills = Path()
        ..moveTo(5, 14)
        ..lineTo(9, 10)
        ..lineTo(12, 13)
        ..lineTo(15, 10)
        ..lineTo(20, 15);
      canvas.drawPath(
        hills,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8
          ..strokeJoin = StrokeJoin.round
          ..color = _pngSky,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(const Rect.fromLTWH(0, 18, 22, 10), const Radius.circular(2)),
        band,
      );
      final tp = TextPainter(
        text: const TextSpan(
          text: 'PNG',
          style: TextStyle(color: Colors.white, fontSize: 7, fontWeight: FontWeight.w700, height: 1),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(11 - tp.width / 2, 23 - tp.height / 2));
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ExportFilePainter old) => old.kind != kind;
}

/// Nút xuất trên màn rộng: icon tệp + chữ ngắn («Excel», «Ảnh PNG»).
class ExportFileButton extends StatelessWidget {
  const ExportFileButton({super.key, required this.kind, required this.tooltip, this.onPressed});

  final ExportFileKind kind;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: ExportFileIcon(kind, size: 20, enabled: onPressed != null),
        label: Text(tr(exportFileShortLabel(kind)), style: const TextStyle(fontSize: 13)),
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF1E293B),
          side: const BorderSide(color: Color(0xFFCBD5E1)),
          padding: const EdgeInsets.fromLTRB(8, 6, 12, 6),
          minimumSize: const Size(0, 36),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
    );
  }
}
