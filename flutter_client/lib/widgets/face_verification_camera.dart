import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:zkteco_flutter_client/widgets/app_responsive_dialog.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/app_permission_service.dart';
import '../services/face_embedding_service_stub.dart'
    if (dart.library.io) '../services/face_embedding_service.dart';
import '../services/mlkit_face_signature_service.dart';

/// Result of face verification: score + captured photo as base64.
class FaceVerificationResult {
  final double matchScore;
  final String? faceImageBase64;
  final bool livenessPassed;
  /// On-device matcher sent to API: tflite | mlkit | null (server path).
  final String? clientFaceEngine;

  FaceVerificationResult({
    required this.matchScore,
    this.faceImageBase64,
    this.livenessPassed = false,
    this.clientFaceEngine,
  });
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

  // Liveness (anti-spoof): require user to blink.
  // Photos and most videos played from another phone cannot produce a blink
  // on demand, so we require observing eyes-open → eyes-closed → eyes-open.
  bool _eyesOpenSeen = false;      // observed open eyes (>= 0.7) at least once
  bool _eyesClosedSeen = false;    // observed closed eyes (< 0.3) after open
  bool _blinkConfirmed = false;    // open again after closed → real blink
  int _frameCountSinceFace = 0;    // guard against infinite wait
  static const _maxFramesForBlink = 180; // ~6s at ~30fps


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
      final permStatus = await AppPermissionService.ensureCameraPermission();
      final allowed = permStatus.isGranted ||
          permStatus.isLimited ||
          await AppPermissionService.hasCameraAccess();
      if (!allowed) {
        if (!mounted) return;
        setState(() => _cameraError = permStatus.isPermanentlyDenied
            ? 'Cần bật Camera trong Cài đặt > SBOX HRM > Quyền'
            : 'Cần cấp quyền camera');
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

      // Minimum face size: reject small faces (e.g. a phone screen held far
      // away showing someone else's photo often appears small in the frame).
      final faceWidth = face.boundingBox.width;
      final frameWidth = inputImage.metadata?.size.width ?? 0;
      if (frameWidth > 0 && faceWidth < frameWidth * 0.25) {
        _updateStatus(_VerifyStatus.waiting, 'Đưa mặt lại gần camera hơn');
        _consecutiveDetections = 0;
        return;
      }

      final leftEyeOpen = face.leftEyeOpenProbability ?? 1.0;
      final rightEyeOpen = face.rightEyeOpenProbability ?? 1.0;

      // Active liveness: blink challenge.
      // 1) See eyes open, 2) see eyes closed, 3) see eyes open again.
      if (!_blinkConfirmed) {
        _frameCountSinceFace++;
        if (_frameCountSinceFace > _maxFramesForBlink) {
          // Reset and ask again
          _frameCountSinceFace = 0;
          _eyesOpenSeen = false;
          _eyesClosedSeen = false;
        }

        final eyesOpen = leftEyeOpen > 0.7 && rightEyeOpen > 0.7;
        final eyesClosed = leftEyeOpen < 0.3 && rightEyeOpen < 0.3;

        if (!_eyesOpenSeen) {
          if (eyesOpen) {
            _eyesOpenSeen = true;
            _updateStatus(_VerifyStatus.waiting, 'Chớp mắt để xác thực');
          } else {
            _updateStatus(_VerifyStatus.waiting, 'Mở mắt nhìn vào camera');
          }
          _consecutiveDetections = 0;
          return;
        }

        if (!_eyesClosedSeen) {
          if (eyesClosed) {
            _eyesClosedSeen = true;
            _updateStatus(_VerifyStatus.waiting, 'Mở mắt ra...');
          } else {
            _updateStatus(_VerifyStatus.waiting, 'Chớp mắt để xác thực');
          }
          _consecutiveDetections = 0;
          return;
        }

        // Eyes closed was seen; now wait for open again to confirm blink
        if (eyesOpen) {
          _blinkConfirmed = true;
          _updateStatus(_VerifyStatus.faceDetected, 'Đã xác thực sự sống. Giữ nguyên...');
        } else {
          _updateStatus(_VerifyStatus.waiting, 'Mở mắt ra...');
          _consecutiveDetections = 0;
          return;
        }
      }

      // Blink confirmed → require eyes to stay open during stability count
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
      // Check if TFLite embedding service is available
      if (!FaceEmbeddingService.isReady) {
        try {
          await FaceEmbeddingService.initialize();
        } catch (e) {
          debugPrint('TFLite init failed: $e');
        }
      }

      if (!FaceEmbeddingService.isReady) {
        // TFLite (MobileFaceNet) not available on this device.
        //
        // On iOS the TensorFlowLiteSwift pod sometimes fails to load on newer
        // SDKs. Instead of forcing server delegation (where the feature-based
        // comparator rejects even legitimate faces), try a second on-device
        // path: Google ML Kit (Apple Vision on iOS) geometric face signature.
        //
        // If that also fails to extract a signature (no face, bad lighting),
        // fall back to the server as last resort.
        final initErr = FaceEmbeddingService.lastInitError ?? '(unknown)';
        debugPrint(
            'TFLite MobileFaceNet not available — trying MLKit signature fallback. lastInitError=$initErr');

        // Persist the error to a log file so the user can retrieve & share it
        // for diagnostics. Also show a dialog (iOS only) so the user can read
        // or screenshot the message before we silently fall through.
        final savedLogPath = await _saveTfliteDiagLog(initErr);
        if (Platform.isIOS && mounted) {
          await _showTfliteDiagDialog(initErr, savedLogPath);
        }

        if (capturedFilePath != null) {
          _updateStatus(_VerifyStatus.verified, 'Đang so sánh khuôn mặt (MLKit)...');
          try {
            final (mlScore, mlDetails) =
                await MlkitFaceSignatureService.compareBestMatch(
              capturedFilePath,
              regPaths,
            );
            debugPrint('MLKit signature compare: score=$mlScore, details=$mlDetails');

            // MLKit signature is less accurate than FaceNet so use a slightly
            // lower threshold than the iOS TFLite min, but still enforce a
            // sane minimum (don't accept anyone).
            final mlMin = math.max(widget.minMatchScore - 5.0, 55.0);
            if (mlScore >= mlMin) {
              _updateStatus(
                _VerifyStatus.verified,
                'Xác thực thành công! Điểm: ${mlScore.toStringAsFixed(0)}',
              );
              _successController.forward();
              final result = FaceVerificationResult(
                matchScore: mlScore,
                faceImageBase64: faceBase64,
                livenessPassed: true,
                clientFaceEngine: 'mlkit',
              );
              await Future.delayed(const Duration(milliseconds: 1200));
              if (mounted) {
                widget.onVerifiedWithImage?.call(result);
                widget.onVerified?.call(result.matchScore);
                widget.onSuccess?.call();
              }
              return;
            }

            if (mlScore > 0) {
              // MLKit ran but score below threshold → tell user to retry
              // rather than silently sending to server which will just say no.
              _updateStatus(_VerifyStatus.error,
                  'Khuôn mặt không khớp (${mlScore.toStringAsFixed(0)}). Vui lòng thử lại.');
              await Future.delayed(const Duration(seconds: 2));
              if (mounted) {
                setState(() {
                  _captured = false;
                  _consecutiveDetections = 0;
                  _progress = 0.0;
                  _eyesOpenSeen = false;
                  _eyesClosedSeen = false;
                  _blinkConfirmed = false;
                  _frameCountSinceFace = 0;
                  _status = _VerifyStatus.waiting;
                  _statusMessage = 'Đưa khuôn mặt vào khung tròn';
                });
                _pulseController.repeat(reverse: true);
                try {
                  await _cameraController?.startImageStream(_onCameraFrame);
                } catch (_) {}
              }
              return;
            }
            // score == 0 means MLKit could not detect / extract signature
            // → fall through to server delegation below.
          } catch (e) {
            debugPrint('MLKit signature fallback failed: $e');
          }
        }

        // Last resort: server comparison (feature-based, strictMin=75).
        _updateStatus(_VerifyStatus.faceDetected, 'Đang gửi ảnh để server xác thực...');
        final result = FaceVerificationResult(
          matchScore: -1,
          faceImageBase64: faceBase64,
          livenessPassed: true,
        );
        await Future.delayed(const Duration(milliseconds: 800));
        if (mounted) {
          widget.onVerifiedWithImage?.call(result);
          widget.onVerified?.call(result.matchScore);
          widget.onSuccess?.call();
        }
        return;
      }

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

      _updateStatus(_VerifyStatus.verified, 'Đang so sánh khuôn mặt (AI)...');

      final (score, details) = await FaceEmbeddingService.compareWithCachedRegistered(
        comparisonBytes,
        regKeys,
        regFaceBytes,
      );

      debugPrint('On-device face comparison: score=$score, details=$details');

      // On iOS require a stricter minimum because there is no second
      // server-side path that can do embedding-based verification — the
      // server comparator is feature-based and can also be spoofed. A real
      // MobileFaceNet match for the same person is typically 70+ on this
      // 0-100 scale, so anything below 65 is treated as a mismatch.
      final effectiveMin = Platform.isIOS
          ? math.max(widget.minMatchScore, 65.0)
          : widget.minMatchScore;

      if (score >= effectiveMin) {
        // Match passed - return result with local score
        _updateStatus(_VerifyStatus.verified, 'Xác thực thành công! Điểm: ${score.toStringAsFixed(0)}');
        _successController.forward();

        final result = FaceVerificationResult(
          matchScore: score,
          faceImageBase64: faceBase64,
          livenessPassed: true,
          clientFaceEngine: 'tflite',
        );

        await Future.delayed(const Duration(milliseconds: 1200));
        if (mounted) {
          widget.onVerifiedWithImage?.call(result);
          widget.onVerified?.call(result.matchScore);
          widget.onSuccess?.call();
        }
      } else if (score <= 0) {
        // Score = 0 likely means embedding extraction failed (TFLite issue).
        // On iOS we do NOT delegate to the server because the server
        // comparator is feature-based and can be spoofed — require the user
        // to retry so we get a real MobileFaceNet score.
        if (Platform.isIOS) {
          debugPrint('On-device comparison returned 0 on iOS, requiring retry');
          _updateStatus(_VerifyStatus.error,
              'Không trích xuất được đặc trưng khuôn mặt. Vui lòng thử lại với ánh sáng tốt hơn.');
          await Future.delayed(const Duration(seconds: 2));
          if (mounted) {
            setState(() {
              _captured = false;
              _consecutiveDetections = 0;
              _progress = 0.0;
              _eyesOpenSeen = false;
              _eyesClosedSeen = false;
              _blinkConfirmed = false;
              _frameCountSinceFace = 0;
              _status = _VerifyStatus.waiting;
              _statusMessage = 'Đưa khuôn mặt vào khung tròn';
            });
            _pulseController.repeat(reverse: true);
            try {
              await _cameraController?.startImageStream(_onCameraFrame);
            } catch (_) {}
          }
        } else {
          // Non-iOS: delegate to server
          debugPrint('On-device comparison returned 0, falling back to server verification');
          _updateStatus(_VerifyStatus.faceDetected, 'Đang gửi ảnh để server xác thực...');

          final result = FaceVerificationResult(
            matchScore: -1,
            faceImageBase64: faceBase64,
            livenessPassed: true,
          );

          await Future.delayed(const Duration(milliseconds: 800));
          if (mounted) {
            widget.onVerifiedWithImage?.call(result);
            widget.onVerified?.call(result.matchScore);
            widget.onSuccess?.call();
          }
        }
      } else {
        // Score > 0 but below threshold = genuine mismatch
        _updateStatus(_VerifyStatus.error,
            'Khuôn mặt không khớp (${score.toStringAsFixed(0)} điểm). Thử lại...');

        await Future.delayed(const Duration(seconds: 2));
        if (mounted) {
          // Reset for retry
          setState(() {
            _captured = false;
            _consecutiveDetections = 0;
            _progress = 0.0;
            _eyesOpenSeen = false;
            _eyesClosedSeen = false;
            _blinkConfirmed = false;
            _frameCountSinceFace = 0;
            _status = _VerifyStatus.waiting;
            _statusMessage = 'Đưa khuôn mặt vào khung tròn';
          });
          _pulseController.repeat(reverse: true);
          try {
            await _cameraController?.startImageStream(_onCameraFrame);
          } catch (_) {}
        }
      }
    } else if (capturedBytes != null && faceBase64 != null) {
      // No registered faces but captured image → send to server for verification
      debugPrint('No registered faces for local comparison, sending to server');
      _updateStatus(_VerifyStatus.faceDetected, 'Đang gửi ảnh để server xác thực...');

      final result = FaceVerificationResult(
        matchScore: -1,
        faceImageBase64: faceBase64,
        livenessPassed: true,
      );

      await Future.delayed(const Duration(milliseconds: 800));
      if (mounted) {
        widget.onVerifiedWithImage?.call(result);
        widget.onVerified?.call(result.matchScore);
        widget.onSuccess?.call();
      }
    } else {
      // No registered faces AND no captured image → fail
      _updateStatus(_VerifyStatus.error, 'Không thể chụp ảnh xác thực.');
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

  /// Persist the TFLite init error to a log file under ApplicationDocuments so
  /// the user (or support) can retrieve it via Files app on iOS. Returns the
  /// absolute path of the log file on success, or null on failure.
  Future<String?> _saveTfliteDiagLog(String initErr) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final f = File('${dir.path}/tflite_init_error.log');
      final ts = DateTime.now().toIso8601String();
      final platform = Platform.isIOS ? 'iOS' : (Platform.isAndroid ? 'Android' : 'Other');
      final content = '[$ts] platform=$platform\n$initErr\n\n';
      await f.writeAsString(content, mode: FileMode.append);
      debugPrint('TFLite diag log saved to: ${f.path}');
      return f.path;
    } catch (e) {
      debugPrint('Failed to save TFLite diag log: $e');
      return null;
    }
  }

  /// Show a modal dialog with the TFLite init error. User must tap "OK" to
  /// dismiss so they have time to screenshot or copy it. Includes a Copy
  /// button to put the message on the clipboard.
  Future<void> _showTfliteDiagDialog(String initErr, String? logPath) async {
    if (!mounted) return;
    final shortErr = initErr.length > 2000 ? '${initErr.substring(0, 2000)}…' : initErr;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => ScrollableAlertDialog(
        title: const Text('Lỗi khởi tạo nhận diện trên máy (iOS)'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Không nạp được TFLite MobileFaceNet trên thiết bị. '
                'Sẽ chuyển sang xác thực qua server. Vui lòng gửi log này cho kỹ thuật:',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
              SelectableText(
                shortErr,
                style: const TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  color: Colors.redAccent,
                ),
              ),
              const SizedBox(height: 12),
              if (logPath != null)
                Text(
                  'Đã lưu log vào:\n$logPath',
                  style: const TextStyle(fontSize: 10, color: Colors.black54),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: initErr));
              if (ctx.mounted) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('Đã copy lỗi vào clipboard')),
                );
              }
            },
            child: const Text('Copy lỗi'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Tiếp tục (dùng server)'),
          ),
        ],
      ),
    );
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
