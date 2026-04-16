// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
import 'dart:convert';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';

class CameraFaceCaptureResult {
  final List<String> base64Images;
  CameraFaceCaptureResult({required this.base64Images});
}

class CameraFaceCapture extends StatefulWidget {
  final String? employeeName;
  final int requiredPhotos;

  const CameraFaceCapture({
    super.key,
    this.employeeName,
    this.requiredPhotos = 3,
  });

  static Future<CameraFaceCaptureResult?> show(
    BuildContext context, {
    String? employeeName,
    int requiredPhotos = 3,
  }) {
    return Navigator.of(context).push<CameraFaceCaptureResult>(
      MaterialPageRoute(
        builder: (_) => CameraFaceCapture(
          employeeName: employeeName,
          requiredPhotos: requiredPhotos,
        ),
      ),
    );
  }

  @override
  State<CameraFaceCapture> createState() => _CameraFaceCaptureState();
}

class _CameraFaceCaptureState extends State<CameraFaceCapture>
    with TickerProviderStateMixin {
  html.VideoElement? _videoElement;
  html.MediaStream? _stream;
  String? _viewId;
  bool _isCameraReady = false;
  bool _isCameraError = false;
  String _errorMessage = '';

  final List<String> _capturedImages = [];
  bool _isCapturing = false;
  bool _showFlash = false;
  int _countdown = 0;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  final List<_CaptureStep> _steps = const [
    _CaptureStep(
      instruction: 'Nhìn thẳng vào camera',
      icon: Icons.face,
    ),
    _CaptureStep(
      instruction: 'Nghiêng mặt sang TRÁI',
      icon: Icons.arrow_back,
    ),
    _CaptureStep(
      instruction: 'Nghiêng mặt sang PHẢI',
      icon: Icons.arrow_forward,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      _viewId = 'face-camera-${DateTime.now().millisecondsSinceEpoch}';

      _videoElement = html.VideoElement()
        ..autoplay = true
        ..muted = true
        ..setAttribute('playsinline', 'true')
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.objectFit = 'cover'
        ..style.transform = 'scaleX(-1)'; // Mirror for selfie

      _stream = await html.window.navigator.mediaDevices!.getUserMedia({
        'video': {
          'facingMode': 'user',
          'width': {'ideal': 640},
          'height': {'ideal': 480},
        },
        'audio': false,
      });

      _videoElement!.srcObject = _stream;
      await _videoElement!.play();

      ui_web.platformViewRegistry.registerViewFactory(
        _viewId!,
        (int id) => _videoElement!,
      );

      if (mounted) setState(() => _isCameraReady = true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isCameraError = true;
          _errorMessage = _getCameraErrorMessage(e.toString());
        });
      }
    }
  }

  String _getCameraErrorMessage(String error) {
    if (error.contains('NotAllowed') || error.contains('Permission')) {
      return 'Trình duyệt chưa cấp quyền camera.\nVui lòng cho phép truy cập camera và thử lại.';
    }
    if (error.contains('NotFound') || error.contains('DevicesNotFound')) {
      return 'Không tìm thấy camera.\nVui lòng kiểm tra thiết bị camera.';
    }
    if (error.contains('NotReadable') || error.contains('TrackStartError')) {
      return 'Camera đang được sử dụng bởi ứng dụng khác.';
    }
    return 'Không thể mở camera: $error';
  }

  int get _currentStep => _capturedImages.length;
  bool get _allCaptured => _capturedImages.length >= widget.requiredPhotos;

  Future<void> _capturePhoto() async {
    if (_isCapturing || _videoElement == null || !_isCameraReady) return;

    setState(() {
      _isCapturing = true;
      _countdown = 3;
    });

    // Countdown 3..2..1
    for (int i = 3; i > 0; i--) {
      if (!mounted) return;
      setState(() => _countdown = i);
      await Future.delayed(const Duration(seconds: 1));
    }

    if (!mounted) return;
    setState(() {
      _showFlash = true;
      _countdown = 0;
    });

    // Capture frame from video
    final vw = _videoElement!.videoWidth;
    final vh = _videoElement!.videoHeight;
    final canvas = html.CanvasElement(width: vw, height: vh);
    final ctx = canvas.context2D;

    // Mirror horizontal to match what user sees
    ctx.translate(vw.toDouble(), 0);
    ctx.scale(-1, 1);
    ctx.drawImage(_videoElement!, 0, 0);

    final dataUrl = canvas.toDataUrl('image/jpeg', 0.85);
    final base64 = dataUrl.split(',').last;

    await Future.delayed(const Duration(milliseconds: 200));

    if (mounted) {
      setState(() {
        _showFlash = false;
        _capturedImages.add(base64);
        _isCapturing = false;
      });
    }
  }

  void _retakePhoto(int index) {
    setState(() {
      _capturedImages.removeAt(index);
    });
  }

  void _resetAll() {
    setState(() => _capturedImages.clear());
  }

  void _stopCamera() {
    _stream?.getTracks().forEach((track) => track.stop());
    _videoElement?.srcObject = null;
  }

  void _confirmAndReturn() {
    _stopCamera();
    Navigator.pop(
      context,
      CameraFaceCaptureResult(base64Images: List.from(_capturedImages)),
    );
  }

  @override
  void dispose() {
    _stopCamera();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(child: _buildCameraSection()),
            _buildBottomSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          _circleButton(Icons.close, () => Navigator.pop(context)),
          const Spacer(),
          if (widget.employeeName != null)
            _pill(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.person, color: Colors.white70, size: 18),
                  const SizedBox(width: 8),
                  Text(widget.employeeName!,
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          const Spacer(),
          _pill(
            child: Text(
              'Ảnh ${_capturedImages.length}/${widget.requiredPhotos}',
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _circleButton(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.15),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 24),
      ),
    );
  }

  Widget _pill({required Widget child}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: child,
    );
  }

  // ── Camera Section ──────────────────────────────────────────

  Widget _buildCameraSection() {
    if (_isCameraError) return _buildCameraError();

    if (!_isCameraReady) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 16),
            Text('Đang mở camera...',
                style: TextStyle(color: Colors.white70, fontSize: 16)),
          ],
        ),
      );
    }

    if (_allCaptured) return _buildCompletionView();

    return Stack(
      alignment: Alignment.center,
      children: [
        // Live camera preview
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 24),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: AspectRatio(
              aspectRatio: 3 / 4,
              child: HtmlElementView(viewType: _viewId!),
            ),
          ),
        ),

        // Face oval guide
        _buildFaceGuide(),

        // Countdown overlay
        if (_countdown > 0)
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.6),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '$_countdown',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 48,
                    fontWeight: FontWeight.bold),
              ),
            ),
          ),

        // Flash effect
        if (_showFlash)
          Positioned.fill(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildFaceGuide() {
    if (_currentStep >= _steps.length) return const SizedBox.shrink();

    final step = _steps[_currentStep];
    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: _isCapturing ? 1.0 : _pulseAnimation.value,
          child: SizedBox(
            width: 220,
            height: 280,
            child: CustomPaint(
              painter: _FaceOvalPainter(
                color: _isCapturing
                    ? const Color(0xFF22C55E)
                    : const Color(0xFF1E3A5F),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(step.icon, color: Colors.white, size: 16),
                        const SizedBox(width: 6),
                        Text(
                          step.instruction,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCameraError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.videocam_off,
                color: Colors.red.shade300, size: 64),
            const SizedBox(height: 16),
            Text(
              _errorMessage,
              style: const TextStyle(color: Colors.white70, fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                setState(() {
                  _isCameraError = false;
                  _isCameraReady = false;
                });
                _initCamera();
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Thử lại'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1E3A5F),
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompletionView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: const Duration(milliseconds: 600),
            curve: Curves.elasticOut,
            builder: (context, value, child) {
              return Transform.scale(
                scale: value,
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E3A5F),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF1E3A5F).withValues(alpha: 0.4),
                        blurRadius: 30,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child:
                      const Icon(Icons.check, color: Colors.white, size: 60),
                ),
              );
            },
          ),
          const SizedBox(height: 24),
          const Text(
            'Chụp ảnh hoàn tất!',
            style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            '${_capturedImages.length} ảnh đã được chụp thành công',
            style: const TextStyle(color: Colors.white70, fontSize: 16),
          ),
          const SizedBox(height: 32),
          // Thumbnails
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: _capturedImages
                .asMap()
                .entries
                .map((e) => _buildThumbnail(e.key, e.value))
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildThumbnail(int index, String base64) {
    return Container(
      width: 80,
      height: 80,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1E3A5F), width: 2),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.memory(base64Decode(base64), fit: BoxFit.cover),
            Positioned(
              top: 2,
              right: 2,
              child: GestureDetector(
                onTap: () => _retakePhoto(index),
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: const BoxDecoration(
                    color: Color(0xFFEF4444),
                    shape: BoxShape.circle,
                  ),
                  child:
                      const Icon(Icons.close, color: Colors.white, size: 14),
                ),
              ),
            ),
            Positioned(
              bottom: 2,
              left: 0,
              right: 0,
              child: Text(
                'Ảnh ${index + 1}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  shadows: [Shadow(blurRadius: 4, color: Colors.black)],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Bottom Section ──────────────────────────────────────────

  Widget _buildBottomSection() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      child: _allCaptured ? _buildCompletionButtons() : _buildCaptureControls(),
    );
  }

  Widget _buildCaptureControls() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Step dots
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(_steps.length, (index) {
            final isCompleted = index < _capturedImages.length;
            final isCurrent = index == _currentStep;
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: isCurrent ? 24 : 10,
              height: 10,
              decoration: BoxDecoration(
                color: isCompleted
                    ? const Color(0xFF1E3A5F)
                    : isCurrent
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(5),
              ),
            );
          }),
        ),
        const SizedBox(height: 12),

        // Show small thumbnails of already-captured
        if (_capturedImages.isNotEmpty) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: _capturedImages
                .asMap()
                .entries
                .map((e) => Container(
                      width: 48,
                      height: 48,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: const Color(0xFF1E3A5F), width: 2),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image.memory(base64Decode(e.value),
                            fit: BoxFit.cover),
                      ),
                    ))
                .toList(),
          ),
          const SizedBox(height: 12),
        ],

        // Capture button
        GestureDetector(
          onTap: (!_isCameraReady || _isCapturing) ? null : _capturePhoto,
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 4),
            ),
            child: Container(
              margin: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _isCapturing ? Colors.red : Colors.white,
              ),
              child: _isCapturing
                  ? const Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : const Icon(Icons.camera,
                      color: Color(0xFF18181B), size: 32),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _isCapturing ? 'Đang chụp...' : 'Nhấn để chụp',
          style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6), fontSize: 13),
        ),
      ],
    );
  }

  Widget _buildCompletionButtons() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _resetAll,
            icon: const Icon(Icons.refresh, color: Colors.white70),
            label: const Text('Chụp lại',
                style: TextStyle(color: Colors.white70)),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          flex: 2,
          child: ElevatedButton.icon(
            onPressed: _confirmAndReturn,
            icon: const Icon(Icons.check),
            label: const Text('Xác nhận & Đăng ký'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1E3A5F),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Models ────────────────────────────────────────────────────

class _CaptureStep {
  final String instruction;
  final IconData icon;

  const _CaptureStep({required this.instruction, required this.icon});
}

// ── Painters ──────────────────────────────────────────────────

class _FaceOvalPainter extends CustomPainter {
  final Color color;
  _FaceOvalPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);

    // Oval stroke
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawOval(rect, paint);

    // Corner brackets
    final bp = Paint()
      ..color = Colors.white.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    const bl = 25.0;
    const o = 12.0;

    // Top-left
    canvas.drawLine(const Offset(o, o + 25), const Offset(o, o + 25 + bl), bp);
    canvas.drawLine(const Offset(o, o + 25), const Offset(o + bl, o + 25), bp);
    // Top-right
    canvas.drawLine(
        Offset(size.width - o, o + 25), Offset(size.width - o, o + 25 + bl), bp);
    canvas.drawLine(
        Offset(size.width - o, o + 25), Offset(size.width - o - bl, o + 25), bp);
    // Bottom-left
    canvas.drawLine(Offset(o, size.height - o - 25),
        Offset(o, size.height - o - 25 - bl), bp);
    canvas.drawLine(Offset(o, size.height - o - 25),
        Offset(o + bl, size.height - o - 25), bp);
    // Bottom-right
    canvas.drawLine(Offset(size.width - o, size.height - o - 25),
        Offset(size.width - o, size.height - o - 25 - bl), bp);
    canvas.drawLine(Offset(size.width - o, size.height - o - 25),
        Offset(size.width - o - bl, size.height - o - 25), bp);
  }

  @override
  bool shouldRepaint(covariant _FaceOvalPainter old) => old.color != color;
}
