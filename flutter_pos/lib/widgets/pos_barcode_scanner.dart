import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:sbox_pos/l10n/app_tr.dart';

/// Nút quét mã vạch / QR bằng camera — dùng làm suffix ô nhập hoặc IconButton riêng.
class PosBarcodeScanIcon extends StatelessWidget {
  const PosBarcodeScanIcon({
    super.key,
    this.controller,
    this.onScanned,
    this.iconSize = 22,
    this.color,
    this.outlined = false,
  });

  final TextEditingController? controller;
  final ValueChanged<String>? onScanned;
  final double iconSize;
  final Color? color;
  final bool outlined;

  Future<void> _scan(BuildContext context) async {
    final code = await scanBarcodeWithCamera(context);
    if (code == null || code.isEmpty) return;
    controller?.text = code;
    onScanned?.call(code);
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tr('Quét mã vạch / QR'),
      icon: Icon(
        outlined ? Icons.qr_code_scanner_outlined : Icons.qr_code_scanner,
        size: iconSize,
        color: color ?? Colors.grey.shade700,
      ),
      onPressed: () => _scan(context),
    );
  }
}

/// Gắn nút quét camera vào [InputDecoration].
InputDecoration posBarcodeScanDecoration(
  InputDecoration base, {
  TextEditingController? controller,
  ValueChanged<String>? onScanned,
  bool outlined = false,
}) {
  return base.copyWith(
    suffixIcon: PosBarcodeScanIcon(
      controller: controller,
      onScanned: onScanned,
      outlined: outlined,
    ),
  );
}

/// Mở camera quét mã vạch một lần, trả về chuỗi mã hoặc null nếu hủy.
Future<String?> scanBarcodeWithCamera(BuildContext context) async {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => const _BarcodeScannerSheet(continuous: false),
  );
}

/// Quét liên tục — mỗi mã hợp lệ gọi [onScan] cho đến khi người dùng bấm Xong.
Future<void> scanBarcodeContinuously(
  BuildContext context, {
  required Future<void> Function(String code) onScan,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => _BarcodeScannerSheet(
      continuous: true,
      onContinuousScan: onScan,
    ),
  );
}

Future<void> _playScanBeep() async {
  try {
    await SystemSound.play(SystemSoundType.click);
  } catch (_) {
    HapticFeedback.heavyImpact();
  }
}

/// Định dạng mã phổ biến — tránh quét `all` làm chậm decode trên Sunmi V2s.
const _kPosScanFormats = <BarcodeFormat>[
  BarcodeFormat.qrCode,
  BarcodeFormat.code128,
  BarcodeFormat.code39,
  BarcodeFormat.code93,
  BarcodeFormat.ean13,
  BarcodeFormat.ean8,
  BarcodeFormat.upcA,
  BarcodeFormat.upcE,
  BarcodeFormat.dataMatrix,
];

class _BarcodeScannerSheet extends StatefulWidget {
  const _BarcodeScannerSheet({
    this.continuous = false,
    this.onContinuousScan,
  });

  final bool continuous;
  final Future<void> Function(String code)? onContinuousScan;

  @override
  State<_BarcodeScannerSheet> createState() => _BarcodeScannerSheetState();
}

class _BarcodeScannerSheetState extends State<_BarcodeScannerSheet> {
  late final MobileScannerController _controller;
  bool _handled = false;
  bool _torchOn = false;
  int _scanCount = 0;
  String? _lastCode;
  DateTime? _lastAt;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.unrestricted,
      facing: CameraFacing.back,
      // 720p thay vì mặc định 640x480 — bắt nét QR nhanh hơn trên V2s.
      formats: _kPosScanFormats,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _toggleTorch() async {
    await _controller.toggleTorch();
    if (!mounted) return;
    setState(() => _torchOn = !_torchOn);
  }

  bool _isDuplicate(String raw) {
    if (_lastCode != raw) return false;
    final at = _lastAt;
    if (at == null) return false;
    return DateTime.now().difference(at).inMilliseconds < 280;
  }

  void _onDetect(BarcodeCapture capture) {
    for (final b in capture.barcodes) {
      final raw = b.rawValue?.trim();
      if (raw == null || raw.isEmpty) continue;

      if (!widget.continuous) {
        if (_handled) return;
        _handled = true;
        // ignore: discarded_futures
        _playScanBeep();
        Navigator.pop(context, raw);
        return;
      }

      if (_isDuplicate(raw)) return;
      _lastCode = raw;
      _lastAt = DateTime.now();
      if (mounted) {
        // ignore: discarded_futures
        _playScanBeep();
        HapticFeedback.mediumImpact();
        setState(() => _scanCount++);
      }
      // ignore: discarded_futures
      widget.onContinuousScan?.call(raw);
      break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.sizeOf(context).height * 0.82;
    final title = widget.continuous ? 'Quét liên tục' : 'Quét mã vạch';
    return SizedBox(
      height: h,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 4, 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tr(title),
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                      if (widget.continuous)
                        Text(tr('Đã quét: $_scanCount'),
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: tr(_torchOn ? 'Tắt đèn' : 'Bật đèn'),
                  onPressed: _toggleTorch,
                  icon: Icon(
                    _torchOn ? Icons.flash_on : Icons.flash_off_outlined,
                    color: _torchOn ? Colors.amber : Colors.grey.shade700,
                  ),
                ),
                if (widget.continuous)
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(tr('Xong')),
                  )
                else
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final size =
                        Size(constraints.maxWidth, constraints.maxHeight);
                    final window = Rect.fromCenter(
                      center: Offset(size.width / 2, size.height / 2),
                      width: size.width * 0.78,
                      height: size.height * 0.36,
                    );
                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        MobileScanner(
                          controller: _controller,
                          onDetect: _onDetect,
                          scanWindow: window,
                        ),
                        IgnorePointer(
                          child: CustomPaint(
                            painter: _ScanReticlePainter(),
                            child: const SizedBox.expand(),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              tr(widget.continuous
                  ? 'Đưa mã vào tâm khung — chạm màn hình để lấy nét. Ưu tiên quét cứng Sunmi nếu có.'
                  : 'Đưa mã vào tâm khung · chạm màn hình để lấy nét nhanh hơn'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScanReticlePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final rectW = size.width * 0.78;
    final rectH = size.height * 0.36;
    final rect = Rect.fromCenter(center: center, width: rectW, height: rectH);

    final dim = Paint()..color = const Color(0x99000000);
    final full = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(full),
        Path()..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(10))),
      ),
      dim,
    );

    final stroke = Paint()
      ..color = Colors.white
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(10)),
      stroke,
    );

    final corner = Paint()
      ..color = const Color(0xFF2563EB)
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    const len = 22.0;
    canvas.drawLine(rect.topLeft, rect.topLeft + const Offset(len, 0), corner);
    canvas.drawLine(rect.topLeft, rect.topLeft + const Offset(0, len), corner);
    canvas.drawLine(rect.topRight, rect.topRight + const Offset(-len, 0), corner);
    canvas.drawLine(rect.topRight, rect.topRight + const Offset(0, len), corner);
    canvas.drawLine(rect.bottomLeft, rect.bottomLeft + const Offset(len, 0), corner);
    canvas.drawLine(rect.bottomLeft, rect.bottomLeft + const Offset(0, -len), corner);
    canvas.drawLine(rect.bottomRight, rect.bottomRight + const Offset(-len, 0), corner);
    canvas.drawLine(rect.bottomRight, rect.bottomRight + const Offset(0, -len), corner);

    canvas.drawCircle(center, 4, Paint()..color = const Color(0xFF2563EB));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
