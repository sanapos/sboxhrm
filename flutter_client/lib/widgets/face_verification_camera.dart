import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:permission_handler/permission_handler.dart';
import '../services/face_embedding_service_stub.dart'
    if (dart.library.io) '../services/face_embedding_service.dart';

/// Result of face verification: score + captured photo as base64.
class FaceVerificationResult {
  final double matchScore;
  final String? faceImageBase64;

  FaceVerificationResult({required this.matchScore, this.faceImageBase64});
}

/// Face verification camera for mobile attendance check-in/out.
/// Uses real camera + ML Kit to detect a real face before allowing punch.
/// When registeredFacePaths are provided, performs on-device face comparison
/// (like a face attendance machine) to reduce server load.
class FaceVerificationCamera extends StatefulWidget {
  final void Function(double matchScore)? onVerified;
  final void Function(FaceVerificationResult result)? onVerifiedWithImage;
  final VoidCallback? onCancel;
  final VoidCallback? onSuccess;
  final List<String>? registeredFacePaths;
  final double minMatchScore;

  const FaceVerificationCamera({
    super.key,
    this.onVerified,
    this.onVerifiedWithImage,
    this.onCancel,
    this.onSuccess,
    this.registeredFacePaths,
    this.minMatchScore = 60.0,
  });

  /// Show the camera and return a [FaceVerificationResult] with score + captured image.
  /// If [registeredFacePaths] are provided, on-device comparison is performed.
  static Future<FaceVerificationResult?> show(
    BuildContext context, {
    List<String>? registeredFacePaths,
    double minMatchScore = 60.0,
  }) async {
    return Navigator.of(context).push<FaceVerificationResult>(
      PageRouteBuilder(
        opaque: true,
        pageBuilder: (ctx, anim, secAnim) => FaceVerificationCamera(
          onVerifiedWithImage: (result) => Navigator.of(ctx).pop(result),
          onCancel: () => Navigator.of(ctx).pop(),
          registeredFacePaths: registeredFacePaths,
          minMatchScore: minMatchScore,
        ),
        transitionsBuilder: (ctx, anim, secAnim, child) {
          return FadeTransition(opacity: anim, child: child);
        },
      ),
    );
  }

  @override
  State<FaceVerificationCamera> createState() => _FaceVerificationCameraState();
}

enum _VerifyStatus { waiting, faceDetected, verified, error }

class _FaceVerificationCameraState extends State<FaceVerificationCamera>
    with TickerProviderStateMixin {
  CameraController? _cameraController;
  late final FaceDetector _faceDetector;
  bool _isCameraReady = false;
  String? _cameraError;
  bool _isProcessingFrame = false;

  _VerifyStatus _status = _VerifyStatus.waiting;
  String _statusMessage = 'Đưa khuôn mặt vào khung tròn';
  int _consecutiveDetections = 0;
  static const _requiredDetections = 8; // ~0.5s of stable face (was 15)
  double _progress = 0.0;
  bool _captured = false;

  late AnimationController _pulseController;
  late AnimationController _successController;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        enableClassification: true,
        enableLandmarks: false,
        enableContours: false,
        performanceMode: FaceDetectorMode.fast,
      ),
    );
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _pulseAnim = Tween(begin: 1.0, end: 1.04).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _successController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      final permStatus = await Permission.camera.request();
      if (permStatus.isDenied || permStatus.isPermanentlyDenied) {
        if (!mounted) return;
        setState(() => _cameraError = 'Cần cấp quyền camera');
        return;
      }

      final cameras = await availableCameras();
      CameraDescription? frontCamera;
      for (final cam in cameras) {
        if (cam.lensDirection == CameraLensDirection.front) frontCamera = cam;
      }
      final selectedCamera = frontCamera ?? cameras.first;

      _cameraController = CameraController(
        selectedCamera,
        ResolutionPreset.medium,
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

      await _cameraController!.startImageStream(_onCameraFrame);
    } catch (e) {
      if (!mounted) return;
      setState(() => _cameraError = 'Không thể mở camera: $e');
    }
  }

  void _onCameraFrame(CameraImage image) {
    if (_isProcessingFrame || _captured || !mounted) return;
    _isProcessingFrame = true;
    _detectFace(image).then((_) => _isProcessingFrame = false);
  }

  Future<void> _detectFace(CameraImage image) async {
    try {
      final inputImage = _buildInputImage(image);
      if (inputImage == null) return;

      final faces = await _faceDetector.processImage(inputImage);
      if (!mounted) return;

      if (faces.isEmpty) {
        _updateStatus(_VerifyStatus.waiting, 'Đưa khuôn mặt vào khung tròn');
        _consecutiveDetections = 0;
        return;
      }

      if (faces.length > 1) {
        _updateStatus(_VerifyStatus.error, 'Chỉ được có 1 khuôn mặt');
        _consecutiveDetections = 0;
        return;
      }

      final face = faces.first;
      final yaw = (face.headEulerAngleY ?? 0).abs();
      final pitch = (face.headEulerAngleX ?? 0).abs();

      // Must be looking roughly straight
      if (yaw > 25 || pitch > 25) {
        _updateStatus(_VerifyStatus.waiting, 'Nhìn thẳng vào camera');
        _consecutiveDetections = 0;
        return;
      }

      // Basic liveness: eyes should be open
      final leftEyeOpen = face.leftEyeOpenProbability ?? 1.0;
      final rightEyeOpen = face.rightEyeOpenProbability ?? 1.0;
      if (leftEyeOpen < 0.3 && rightEyeOpen < 0.3) {
        _updateStatus(_VerifyStatus.waiting, 'Vui lòng mở mắt');
        _consecutiveDetections = 0;
        return;
      }

      _consecutiveDetections++;
      final progress = (_consecutiveDetections / _requiredDetections).clamp(0.0, 1.0);
      setState(() => _progress = progress);

      if (_consecutiveDetections < _requiredDetections) {
        _updateStatus(_VerifyStatus.faceDetected, 'Giữ nguyên... ${(progress * 100).toInt()}%');
      } else {
        _captureAndComplete();
      }
    } catch (e) {
      debugPrint('Face verify error: $e');
    }
  }

  InputImage? _buildInputImage(CameraImage image) {
    final camera = _cameraController!.description;
    final sensorOrientation = camera.sensorOrientation;
    final rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
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

  Future<void> _captureAndComplete() async {
    if (_captured) return;
    _captured = true;

    try {
      await _cameraController?.stopImageStream();
    } catch (_) {}

    _updateStatus(_VerifyStatus.verified, 'Đang chụp ảnh xác thực...');
    _pulseController.stop();

    // Capture a photo
    Uint8List? capturedBytes;
    String? faceBase64;
    String? capturedFilePath;
    try {
      final xFile = await _cameraController?.takePicture();
      if (xFile != null) {
        capturedBytes = await xFile.readAsBytes();
        capturedFilePath = xFile.path;
        faceBase64 = base64Encode(capturedBytes);
      }
    } catch (e) {
      debugPrint('Error capturing face photo: $e');
    }

    // On-device face comparison if registered faces are available
    final regPaths = widget.registeredFacePaths;
    if (regPaths != null && regPaths.isNotEmpty && capturedBytes != null) {
      _updateStatus(_VerifyStatus.verified, 'Đang nhận dạng khuôn mặt...');

      // ML Kit face detection + crop for accurate comparison
      Uint8List comparisonBytes = capturedBytes;
      if (capturedFilePath != null) {
        final cropped = await _detectAndCropFace(capturedFilePath);
        if (cropped != null) {
          comparisonBytes = cropped;
          debugPrint('Captured: ML Kit face crop OK');
        } else {
          debugPrint('Captured: ML Kit no face, using full image');
        }
      }

      // Crop faces from registered images (first time only, then cached by embedding service)
      final regFaceBytes = <Uint8List>[];
      final regKeys = <String>[];
      for (final path in regPaths) {
        final cropped = await _detectAndCropFace(path);
        if (cropped != null) {
          regFaceBytes.add(cropped);
          regKeys.add('reg_$path');
        } else {
          regFaceBytes.add(await File(path).readAsBytes());
          regKeys.add('reg_orig_$path');
        }
      }

      _updateStatus(_VerifyStatus.verified, '\u0110ang so s\u00e1nh khu\u00f4n m\u1eb7t (AI)...');

      final (score, details) = await FaceEmbeddingService.compareWithCachedRegistered(
        comparisonBytes,
        regKeys,
        regFaceBytes,
      );

      debugPrint('On-device face comparison: score=$score, details=$details');

      if (score >= widget.minMatchScore) {
        // Match passed - return result with local score
        _updateStatus(_VerifyStatus.verified, 'Xác thực thành công! Điểm: ${score.toStringAsFixed(0)}');
        _successController.forward();

        final result = FaceVerificationResult(
          matchScore: score,
          faceImageBase64: faceBase64,
        );

        await Future.delayed(const Duration(milliseconds: 1200));
        if (mounted) {
          widget.onVerifiedWithImage?.call(result);
          widget.onVerified?.call(result.matchScore);
          widget.onSuccess?.call();
        }
      } else {
        // Match failed - show error and allow retry
        _updateStatus(_VerifyStatus.error,
            'Khuôn mặt không khớp (${score.toStringAsFixed(0)} điểm). Thử lại...');

        await Future.delayed(const Duration(seconds: 2));
        if (mounted) {
          // Reset for retry
          setState(() {
            _captured = false;
            _consecutiveDetections = 0;
            _progress = 0.0;
            _status = _VerifyStatus.waiting;
            _statusMessage = 'Đưa khuôn mặt vào khung tròn';
          });
          _pulseController.repeat(reverse: true);
          try {
            await _cameraController?.startImageStream(_onCameraFrame);
          } catch (_) {}
        }
      }
    } else {
      // No registered faces for local comparison → BLOCK, don't allow bypass
      _updateStatus(_VerifyStatus.error, 'Chưa có dữ liệu khuôn mặt đăng ký. Không thể xác thực.');
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) {
        Navigator.of(context).pop(null); // Return null = failed
      }
    }
  }

  /// Detect face in image file using ML Kit, crop to bounding box with padding.
  /// Returns face-cropped JPEG bytes, or null if no face detected.
  Future<Uint8List?> _detectAndCropFace(String filePath) async {
    try {
      final inputImage = InputImage.fromFilePath(filePath);
      final detectedFaces = await _faceDetector.processImage(inputImage);
      if (detectedFaces.isEmpty) return null;

      final bbox = detectedFaces.first.boundingBox;
      final fileBytes = await File(filePath).readAsBytes();

      var decoded = img.decodeImage(fileBytes);
      if (decoded == null) return null;
      decoded = img.bakeOrientation(decoded);

      // 25% padding around face bounding box
      final padW = (bbox.width * 0.25).round();
      final padH = (bbox.height * 0.25).round();
      final x = (bbox.left.round() - padW).clamp(0, decoded.width - 1);
      final y = (bbox.top.round() - padH).clamp(0, decoded.height - 1);
      final w = (bbox.width.round() + padW * 2).clamp(1, decoded.width - x);
      final h = (bbox.height.round() + padH * 2).clamp(1, decoded.height - y);

      final cropped = img.copyCrop(decoded, x: x, y: y, width: w, height: h);
      debugPrint('Face crop: bbox=${bbox.width.round()}x${bbox.height.round()} '
          '→ ${cropped.width}x${cropped.height} from ${decoded.width}x${decoded.height}');

      return Uint8List.fromList(img.encodeJpg(cropped, quality: 95));
    } catch (e) {
      debugPrint('Face crop error: $e');
      return null;
    }
  }

  void _updateStatus(_VerifyStatus status, String msg) {
    if (!mounted) return;
    setState(() {
      _status = status;
      _statusMessage = msg;
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _successController.dispose();
    _faceDetector.close();
    _cameraController?.dispose();
    super.dispose();
  }

  Color get _borderColor {
    switch (_status) {
      case _VerifyStatus.waiting:
        return Colors.white54;
      case _VerifyStatus.faceDetected:
        return const Color(0xFF3B82F6);
      case _VerifyStatus.verified:
        return const Color(0xFF22C55E);
      case _VerifyStatus.error:
        return const Color(0xFFEF4444);
    }
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

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final size = mq.size;
    final circleSize = size.width * 0.68;
    final circleTop = size.height * 0.38;

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
                  builder: (ctx, c) => _buildCameraPreview(c),
                ),
              ),

            // 2. Dark overlay with circular cutout
            if (_isCameraReady)
              Positioned.fill(
                child: CustomPaint(
                  painter: _CircleCutoutPainter(
                    circleSize: circleSize,
                    centerY: circleTop,
                  ),
                ),
              ),

            // 3. Animated progress circle border
            if (_isCameraReady)
              Positioned(
                left: (size.width - circleSize) / 2,
                top: circleTop - circleSize / 2,
                child: AnimatedBuilder(
                  animation: _pulseAnim,
                  builder: (ctx, _) {
                    return Transform.scale(
                      scale: _captured ? 1.0 : _pulseAnim.value,
                      child: SizedBox(
                        width: circleSize,
                        height: circleSize,
                        child: CustomPaint(
                          painter: _ProgressCirclePainter(
                            progress: _progress,
                            baseColor: _borderColor,
                            trackColor: Colors.white24,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),

            // 4. Success checkmark
            if (_status == _VerifyStatus.verified)
              Positioned(
                left: 0,
                right: 0,
                top: circleTop - 36,
                child: ScaleTransition(
                  scale: CurvedAnimation(
                    parent: _successController,
                    curve: Curves.elasticOut,
                  ),
                  child: const Center(
                    child: CircleAvatar(
                      radius: 36,
                      backgroundColor: Color(0xFF22C55E),
                      child: Icon(Icons.check, color: Colors.white, size: 40),
                    ),
                  ),
                ),
              ),

            // 5. Status badge below circle
            if (_isCameraReady)
              Positioned(
                left: 24,
                right: 24,
                top: circleTop + circleSize / 2 + 20,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: Container(
                    key: ValueKey(_statusMessage),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    decoration: BoxDecoration(
                      color: _borderColor.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _status == _VerifyStatus.verified
                              ? Icons.check_circle
                              : _status == _VerifyStatus.faceDetected
                                  ? Icons.face
                                  : _status == _VerifyStatus.error
                                      ? Icons.warning_amber_rounded
                                      : Icons.face_retouching_off,
                          color: Colors.white,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            _statusMessage,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
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

            // 6. Bottom panel
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: EdgeInsets.fromLTRB(24, 28, 24, mq.padding.bottom + 24),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black54, Colors.black87],
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Xác thực khuôn mặt',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Nhìn thẳng vào camera và giữ nguyên',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 24),
                    if (!_captured)
                      TextButton(
                        onPressed: widget.onCancel,
                        child: const Text(
                          'Huỷ bỏ',
                          style: TextStyle(color: Colors.white54, fontSize: 16),
                        ),
                      ),
                  ],
                ),
              ),
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

            // 9. Loading
            if (!_isCameraReady && _cameraError == null)
              const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Colors.white),
                    SizedBox(height: 16),
                    Text('Đang mở camera...',
                        style: TextStyle(color: Colors.white70, fontSize: 16)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
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
    canvas.drawPath(path, Paint()..color = Colors.black.withValues(alpha: 0.55));
  }

  @override
  bool shouldRepaint(covariant _CircleCutoutPainter old) =>
      old.circleSize != circleSize || old.centerY != centerY;
}

class _ProgressCirclePainter extends CustomPainter {
  final double progress;
  final Color baseColor;
  final Color trackColor;

  _ProgressCirclePainter({
    required this.progress,
    required this.baseColor,
    required this.trackColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 3;
    const strokeWidth = 4.0;

    // Track circle
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = trackColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth,
    );

    // Progress arc
    if (progress > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,
        2 * math.pi * progress,
        false,
        Paint()
          ..color = baseColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ProgressCirclePainter old) =>
      old.progress != progress || old.baseColor != baseColor;
}
