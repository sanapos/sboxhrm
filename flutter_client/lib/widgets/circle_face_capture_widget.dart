import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:permission_handler/permission_handler.dart';

/// iPhone-style circular face registration with ML Kit face detection.
/// Only captures when a face is detected AND matches the required direction.
class CircleFaceCaptureWidget extends StatefulWidget {
  final void Function(List<String> images)? onComplete;
  final VoidCallback? onCancel;

  const CircleFaceCaptureWidget({
    super.key,
    this.onComplete,
    this.onCancel,
  });

  static Future<List<String>?> show(BuildContext context) {
    return Navigator.of(context).push<List<String>>(
      PageRouteBuilder(
        opaque: true,
        pageBuilder: (ctx, anim, secAnim) => CircleFaceCaptureWidget(
          onComplete: (images) => Navigator.of(ctx).pop(images),
          onCancel: () => Navigator.of(ctx).pop(),
        ),
        transitionsBuilder: (ctx, anim, secAnim, child) {
          return FadeTransition(opacity: anim, child: child);
        },
      ),
    );
  }

  @override
  State<CircleFaceCaptureWidget> createState() =>
      _CircleFaceCaptureWidgetState();
}

/// Face detection status for UI feedback.
enum _FaceStatus {
  noFace,        // No face detected
  wrongDirection, // Face detected but wrong direction
  aligned,       // Face detected and correct direction
}

class _CircleFaceCaptureWidgetState extends State<CircleFaceCaptureWidget>
    with TickerProviderStateMixin {
  CameraController? _cameraController;
  bool _isCameraReady = false;
  String? _cameraError;

  int _currentStep = 0;
  bool _isCapturing = false;
  bool _allDone = false;
  final List<String> _capturedImages = [];

  // Face detection
  late final FaceDetector _faceDetector;
  bool _isProcessingFrame = false;
  _FaceStatus _faceStatus = _FaceStatus.noFace;
  String _faceHint = '';
  // Hold progress: only advances while face is aligned
  double _stepProgress = 0.0;
  Timer? _progressTimer;

  late AnimationController _pulseController;
  late AnimationController _segmentController;
  late AnimationController _successController;
  late Animation<double> _pulseAnim;

  static const _steps = [
    _FaceStep('Nhìn thẳng vào camera', Icons.face, 'front'),
    _FaceStep('Quay mặt sang TRÁI', Icons.chevron_left, 'left'),
    _FaceStep('Quay mặt sang PHẢI', Icons.chevron_right, 'right'),
    _FaceStep('Ngẩng mặt lên TRÊN', Icons.expand_less, 'up'),
    _FaceStep('Cúi mặt xuống DƯỚI', Icons.expand_more, 'down'),
  ];

  // Direction thresholds (euler angles in degrees)
  // headEulerAngleY: positive = face turned LEFT (from camera's view), negative = RIGHT
  // headEulerAngleX: positive = face looking UP, negative = DOWN
  // Note: front camera mirrors, so Y is inverted for user perception
  static const double _yawThreshold = 20.0;     // Min yaw for left/right
  static const double _pitchThreshold = 15.0;    // Min pitch for up/down
  static const double _frontMaxAngle = 12.0;     // Max angle for "straight"

  @override
  void initState() {
    super.initState();
    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        enableClassification: false,
        enableLandmarks: false,
        enableContours: false,
        enableTracking: false,
        performanceMode: FaceDetectorMode.fast,
      ),
    );
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _pulseAnim = Tween(begin: 1.0, end: 1.06).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _segmentController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _successController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      final status = await Permission.camera.request();
      if (status.isDenied || status.isPermanentlyDenied) {
        if (!mounted) return;
        setState(() => _cameraError =
            'Cần cấp quyền camera để đăng ký khuôn mặt.\nVui lòng vào Cài đặt > Quyền ứng dụng để cấp quyền.');
        return;
      }

      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (!mounted) return;
        setState(() => _cameraError = 'Không tìm thấy camera nào.');
        return;
      }

      CameraDescription? frontCamera;
      for (final cam in cameras) {
        if (cam.lensDirection == CameraLensDirection.front) {
          frontCamera = cam;
        }
      }
      final selectedCamera = frontCamera ?? cameras.first;

      _cameraController = CameraController(
        selectedCamera,
        ResolutionPreset.medium, // medium for faster ML processing
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.nv21
            : ImageFormatGroup.bgra8888,
      );

      await _cameraController!.initialize();
      try {
        await _cameraController!.lockCaptureOrientation(DeviceOrientation.portraitUp);
      } catch (_) {}

      if (!mounted) return;
      setState(() => _isCameraReady = true);

      // Start image stream for face detection
      await _cameraController!.startImageStream(_onCameraFrame);

      Future.delayed(const Duration(milliseconds: 800), () {
        if (mounted) _startStep();
      });
    } catch (e) {
      debugPrint('📸 Error: $e');
      if (!mounted) return;
      setState(() => _cameraError = 'Không thể mở camera:\n$e');
    }
  }

  /// Process each camera frame for face detection.
  void _onCameraFrame(CameraImage image) {
    if (_isProcessingFrame || _allDone || !mounted) return;
    _isProcessingFrame = true;
    _detectFace(image).then((_) {
      _isProcessingFrame = false;
    });
  }

  Future<void> _detectFace(CameraImage image) async {
    try {
      final inputImage = _buildInputImage(image);
      if (inputImage == null) return;

      final faces = await _faceDetector.processImage(inputImage);

      if (!mounted) return;

      if (faces.isEmpty) {
        _updateFaceStatus(_FaceStatus.noFace, 'Không phát hiện khuôn mặt');
        return;
      }

      if (faces.length > 1) {
        _updateFaceStatus(_FaceStatus.noFace, 'Chỉ được có 1 khuôn mặt');
        return;
      }

      final face = faces.first;
      final yaw = face.headEulerAngleY ?? 0.0;   // left/right
      final pitch = face.headEulerAngleX ?? 0.0;  // up/down

      final step = _steps[_currentStep];
      final isAligned = _checkDirection(step.direction, yaw, pitch);

      if (isAligned) {
        _updateFaceStatus(_FaceStatus.aligned, _getAlignedHint(step.direction));
      } else {
        _updateFaceStatus(
          _FaceStatus.wrongDirection,
          _getDirectionHint(step.direction, yaw, pitch),
        );
      }
    } catch (e) {
      debugPrint('📸 ML Kit error: $e');
    }
  }

  InputImage? _buildInputImage(CameraImage image) {
    final camera = _cameraController!.description;
    final sensorOrientation = camera.sensorOrientation;

    InputImageRotation? rotation;
    if (Platform.isAndroid) {
      // Front camera on Android: rotation = (sensorOrientation + deviceRotation) % 360
      // Since we lock portrait, deviceRotation = 0
      final rotationCompensation = sensorOrientation;
      rotation = InputImageRotationValue.fromRawValue(rotationCompensation);
    } else {
      rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
    }
    if (rotation == null) return null;

    final format = Platform.isAndroid
        ? InputImageFormat.nv21
        : InputImageFormat.bgra8888;

    final plane = image.planes.first;

    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  /// Check if face direction matches the required step.
  bool _checkDirection(String direction, double yaw, double pitch) {
    switch (direction) {
      case 'front':
        return yaw.abs() < _frontMaxAngle && pitch.abs() < _frontMaxAngle;
      case 'left':
        // Front camera mirrors: positive yaw = user's left
        return yaw > _yawThreshold;
      case 'right':
        return yaw < -_yawThreshold;
      case 'up':
        return pitch > _pitchThreshold;
      case 'down':
        return pitch < -_pitchThreshold;
      default:
        return false;
    }
  }

  String _getAlignedHint(String direction) {
    switch (direction) {
      case 'front': return 'Giữ nguyên...';
      case 'left': return 'Tốt! Giữ nguyên...';
      case 'right': return 'Tốt! Giữ nguyên...';
      case 'up': return 'Tốt! Giữ nguyên...';
      case 'down': return 'Tốt! Giữ nguyên...';
      default: return '';
    }
  }

  String _getDirectionHint(String direction, double yaw, double pitch) {
    switch (direction) {
      case 'front':
        if (yaw.abs() > pitch.abs()) {
          return yaw > 0 ? 'Quay mặt sang phải thêm' : 'Quay mặt sang trái thêm';
        }
        return pitch > 0 ? 'Cúi mặt xuống thêm' : 'Ngẩng mặt lên thêm';
      case 'left': return 'Quay mặt sang trái nhiều hơn';
      case 'right': return 'Quay mặt sang phải nhiều hơn';
      case 'up': return 'Ngẩng mặt lên cao hơn';
      case 'down': return 'Cúi mặt xuống thấp hơn';
      default: return '';
    }
  }

  void _updateFaceStatus(_FaceStatus status, String hint) {
    if (!mounted) return;
    setState(() {
      _faceStatus = status;
      _faceHint = hint;
    });


  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    _pulseController.dispose();
    _segmentController.dispose();
    _successController.dispose();
    _faceDetector.close();
    _cameraController?.dispose();
    super.dispose();
  }

  void _startStep() {
    if (_currentStep >= _steps.length || !mounted) return;
    setState(() {
      _isCapturing = true;
      _stepProgress = 0.0;
      _faceStatus = _FaceStatus.noFace;
      _faceHint = '';
    });

    // Progress timer: only advances when face is aligned
    const tick = Duration(milliseconds: 50);
    const totalTicks = 40; // 40 * 50ms = 2 seconds of aligned face needed

    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(tick, (t) {
      if (!mounted) { t.cancel(); return; }

      if (_faceStatus == _FaceStatus.aligned) {
        setState(() {
          _stepProgress = (_stepProgress + 1.0 / totalTicks).clamp(0.0, 1.0);
        });
        if (_stepProgress >= 1.0) {
          t.cancel();
          _captureAndAdvance();
        }
      } else {
        // Slowly decay progress when face not aligned (don't reset instantly)
        if (_stepProgress > 0) {
          setState(() {
            _stepProgress = (_stepProgress - 0.5 / totalTicks).clamp(0.0, 1.0);
          });
        }
      }
    });
  }

  Future<void> _captureAndAdvance() async {
    // Stop image stream temporarily for clean capture
    try {
      await _cameraController?.stopImageStream();
    } catch (_) {}

    String base64Image = '';
    XFile? xFile;
    try {
      if (_cameraController != null && _cameraController!.value.isInitialized) {
        xFile = await _cameraController!.takePicture();
      }
    } catch (e) {
      debugPrint('📸 Capture error: $e');
    }

    // Restart image stream IMMEDIATELY after capture (before processing file)
    // This minimizes the camera preview freeze on iOS
    if (_currentStep < _steps.length - 1) {
      try {
        await _cameraController?.startImageStream(_onCameraFrame);
      } catch (_) {}
    }

    // Process captured file in parallel with stream restart
    if (xFile != null) {
      try {
        final bytes = await File(xFile.path).readAsBytes();
        base64Image = base64Encode(bytes);
        try { await File(xFile.path).delete(); } catch (_) {}
      } catch (_) {}
    }

    if (!mounted) return;
    _capturedImages.add(base64Image);
    setState(() => _isCapturing = false);
    _segmentController.forward(from: 0);

    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;

    if (_currentStep < _steps.length - 1) {
      setState(() => _currentStep++);
      _startStep();
    } else {
      _onAllDone();
    }
  }

  void _onAllDone() {
    setState(() => _allDone = true);
    _pulseController.stop();
    _successController.forward();
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) widget.onComplete?.call(_capturedImages);
    });
  }

  Widget _buildCameraPreview(BoxConstraints constraints) {
    final controller = _cameraController!;
    final double cameraAR = controller.value.aspectRatio;
    final double portraitCameraAR = 1.0 / cameraAR;

    double scaleX = constraints.maxWidth / (constraints.maxHeight * portraitCameraAR);
    double scaleY = 1.0;
    if (scaleX < 1.0) {
      scaleY = 1.0 / scaleX;
      scaleX = 1.0;
    }
    final scale = math.max(scaleX, scaleY);

    return ClipRect(
      child: OverflowBox(
        maxWidth: double.infinity,
        maxHeight: double.infinity,
        child: Transform.scale(
          scale: scale,
          child: Center(
            child: SizedBox(
              width: constraints.maxWidth,
              height: constraints.maxWidth / portraitCameraAR,
              child: CameraPreview(controller),
            ),
          ),
        ),
      ),
    );
  }

  /// Color of circle border based on face status.
  Color get _statusColor {
    switch (_faceStatus) {
      case _FaceStatus.noFace: return const Color(0xFFEF4444); // red
      case _FaceStatus.wrongDirection: return const Color(0xFFFBBF24); // yellow
      case _FaceStatus.aligned: return const Color(0xFF22C55E); // green
    }
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final size = mq.size;
    final circleSize = size.width * 0.72;
    final circleTop = size.height * 0.35;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            // 1. Camera preview
            if (_isCameraReady && _cameraController != null)
              Positioned.fill(
                child: LayoutBuilder(
                  builder: (ctx, constraints) => _buildCameraPreview(constraints),
                ),
              ),

            // 2. Dark overlay with circular hole
            if (_isCameraReady)
              Positioned.fill(
                child: CustomPaint(
                  painter: _CircleCutoutPainter(
                    circleSize: circleSize,
                    centerY: circleTop,
                  ),
                ),
              ),

            // 3. Segmented circle border with pulse + status color
            if (_isCameraReady)
              Positioned(
                left: (size.width - circleSize) / 2,
                top: circleTop - circleSize / 2,
                child: AnimatedBuilder(
                  animation: _pulseAnim,
                  builder: (ctx, child) {
                    return Transform.scale(
                      scale: _allDone ? 1.0 : _pulseAnim.value,
                      child: SizedBox(
                        width: circleSize,
                        height: circleSize,
                        child: CustomPaint(
                          painter: _SegmentedCirclePainter(
                            totalSteps: _steps.length,
                            completedSteps: _capturedImages.length,
                            currentProgress: _isCapturing ? _stepProgress : 0,
                            isComplete: _allDone,
                            activeColor: _statusColor,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),

            // 4. Green checkmark on complete
            if (_allDone)
              Positioned(
                left: 0,
                right: 0,
                top: circleTop - 40,
                child: ScaleTransition(
                  scale: CurvedAnimation(
                    parent: _successController,
                    curve: Curves.elasticOut,
                  ),
                  child: const Center(
                    child: CircleAvatar(
                      radius: 40,
                      backgroundColor: Color(0xFF22C55E),
                      child: Icon(Icons.check, color: Colors.white, size: 44),
                    ),
                  ),
                ),
              ),

            // 5. Face status hint (below circle)
            if (_isCameraReady && !_allDone && _isCapturing)
              Positioned(
                left: 24,
                right: 24,
                top: circleTop + circleSize / 2 + 16,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: Container(
                    key: ValueKey(_faceHint),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: _statusColor.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _faceStatus == _FaceStatus.noFace
                              ? Icons.face_retouching_off
                              : _faceStatus == _FaceStatus.wrongDirection
                                  ? Icons.warning_amber_rounded
                                  : Icons.check_circle,
                          color: Colors.white,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            _faceHint.isEmpty ? '...' : _faceHint,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // 6. Bottom instruction panel
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _buildBottomPanel(mq.padding.bottom),
            ),

            // 7. Close button
            Positioned(
              top: mq.padding.top + 8,
              left: 8,
              child: IconButton(
                onPressed: widget.onCancel,
                icon: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.black38,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(Icons.close, color: Colors.white, size: 24),
                ),
              ),
            ),

            // 8. Camera error
            if (_cameraError != null)
              Center(
                child: Container(
                  margin: const EdgeInsets.all(32),
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.camera_alt_outlined,
                          color: Colors.white54, size: 48),
                      const SizedBox(height: 16),
                      Text(
                        _cameraError!,
                        style: const TextStyle(color: Colors.white, fontSize: 16),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton(
                        onPressed: () => openAppSettings(),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white24,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Mở Cài đặt'),
                      ),
                    ],
                  ),
                ),
              ),

            // 9. Loading indicator
            if (!_isCameraReady && _cameraError == null)
              const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Colors.white),
                    SizedBox(height: 16),
                    Text(
                      'Đang mở camera...',
                      style: TextStyle(color: Colors.white70, fontSize: 16),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomPanel(double bottomPadding) {
    final step = _currentStep < _steps.length ? _steps[_currentStep] : null;

    return Container(
      padding: EdgeInsets.fromLTRB(24, 28, 24, bottomPadding + 24),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black45, Colors.black54],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Step dots
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(_steps.length, (i) {
              final done = i < _capturedImages.length;
              final current = i == _currentStep && !_allDone;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: current ? 28 : 10,
                height: 10,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: done
                      ? const Color(0xFF22C55E)
                      : current
                          ? Colors.white
                          : Colors.white24,
                  borderRadius: BorderRadius.circular(5),
                ),
              );
            }),
          ),
          const SizedBox(height: 20),

          if (_allDone)
            const Text(
              'Đăng ký khuôn mặt hoàn tất!',
              style: TextStyle(
                color: Color(0xFF22C55E),
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            )
          else if (step != null) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(step.icon, color: Colors.white, size: 28),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    step.instruction,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Bước ${_currentStep + 1} / ${_steps.length}',
              style: const TextStyle(color: Colors.white54, fontSize: 14),
            ),
          ],

          const SizedBox(height: 20),
          if (!_allDone)
            TextButton(
              onPressed: widget.onCancel,
              child: const Text(
                'Huỷ bỏ',
                style: TextStyle(color: Colors.white54, fontSize: 16),
              ),
            ),
        ],
      ),
    );
  }
}

class _FaceStep {
  final String instruction;
  final IconData icon;
  final String direction;
  const _FaceStep(this.instruction, this.icon, this.direction);
}

class _CircleCutoutPainter extends CustomPainter {
  final double circleSize;
  final double centerY;
  _CircleCutoutPainter({required this.circleSize, required this.centerY});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, centerY);
    final radius = circleSize / 2;
    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addOval(Rect.fromCircle(center: center, radius: radius))
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(path, Paint()..color = Colors.black.withValues(alpha: 0.4));
  }

  @override
  bool shouldRepaint(covariant _CircleCutoutPainter old) =>
      old.circleSize != circleSize || old.centerY != centerY;
}

class _SegmentedCirclePainter extends CustomPainter {
  final int totalSteps;
  final int completedSteps;
  final double currentProgress;
  final bool isComplete;
  final Color activeColor;

  _SegmentedCirclePainter({
    required this.totalSteps,
    required this.completedSteps,
    required this.currentProgress,
    required this.isComplete,
    this.activeColor = Colors.white,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 4;
    const strokeWidth = 5.0;
    const gapDegrees = 6.0;
    final segmentDegrees = (360 - gapDegrees * totalSteps) / totalSteps;

    for (int i = 0; i < totalSteps; i++) {
      final startAngle =
          (-90 + i * (segmentDegrees + gapDegrees)) * math.pi / 180;

      Color color;
      double sweepFraction = 1.0;

      if (isComplete) {
        color = const Color(0xFF22C55E);
      } else if (i < completedSteps) {
        color = const Color(0xFF22C55E);
      } else if (i == completedSteps) {
        color = activeColor;
        sweepFraction = currentProgress;
      } else {
        color = Colors.white24;
      }

      final sweepAngle = segmentDegrees * sweepFraction * math.pi / 180;

      if (i == completedSteps && !isComplete) {
        canvas.drawArc(
          Rect.fromCircle(center: center, radius: radius),
          startAngle,
          segmentDegrees * math.pi / 180,
          false,
          Paint()
            ..color = Colors.white24
            ..style = PaintingStyle.stroke
            ..strokeWidth = strokeWidth
            ..strokeCap = StrokeCap.round,
        );
      }

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        false,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SegmentedCirclePainter old) =>
      old.completedSteps != completedSteps ||
      old.currentProgress != currentProgress ||
      old.isComplete != isComplete ||
      old.activeColor != activeColor;
}
