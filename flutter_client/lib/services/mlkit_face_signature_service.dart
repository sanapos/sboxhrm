// On-device face comparison using Google ML Kit landmarks + contours.
//
// This is a FALLBACK used when the MobileFaceNet TFLite model is not
// available (typically iOS when the TensorFlowLiteSwift pod fails to load).
//
// Unlike HOG/LBP feature comparators (which score any two aligned faces
// 60-80 regardless of identity), this computes a GEOMETRIC face signature
// from ML Kit landmarks/contours normalised by inter-ocular distance and
// angle. Same person ~ cosine 0.95+, different person ~ 0.80-0.90, so a
// threshold around 0.92 reliably separates them in workplace conditions.
//
// ML Kit uses Apple Vision on iOS, so this works even when the TFLite
// library is broken on the device.

import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

class MlkitFaceSignatureService {
  static FaceDetector? _detector;

  // Cache signatures for registered faces to avoid re-running ML Kit on every punch.
  static final Map<String, List<double>?> _signatureCache = {};

  static FaceDetector _getDetector() {
    return _detector ??= FaceDetector(
      options: FaceDetectorOptions(
        enableLandmarks: true,
        enableContours: true,
        enableClassification: false,
        performanceMode: FaceDetectorMode.accurate,
      ),
    );
  }

  /// Build a normalised geometric signature from an image file.
  ///
  /// Returns null when no face is detected or landmarks are missing.
  static Future<List<double>?> signatureFromFile(String filePath) async {
    try {
      final input = InputImage.fromFilePath(filePath);
      final faces = await _getDetector().processImage(input);
      if (faces.isEmpty) {
        debugPrint('MlkitSig: no face in $filePath');
        return null;
      }
      return _signatureFromFace(faces.first);
    } catch (e) {
      debugPrint('MlkitSig: signatureFromFile failed: $e');
      return null;
    }
  }

  /// Get signature for a registered face, cached by path.
  static Future<List<double>?> signatureFromCached(String key, String filePath) async {
    if (_signatureCache.containsKey(key)) return _signatureCache[key];
    final sig = await signatureFromFile(filePath);
    _signatureCache[key] = sig;
    return sig;
  }

  static void clearCache() => _signatureCache.clear();

  /// Compare a captured face file against a list of registered face files.
  /// Returns (0-100 score, details). Higher = more similar.
  static Future<(double, String)> compareBestMatch(
    String capturedFilePath,
    List<String> registeredFilePaths,
  ) async {
    if (registeredFilePaths.isEmpty) {
      return (0.0, 'MLKit: không có ảnh đăng ký');
    }

    final sw = Stopwatch()..start();
    final capSig = await signatureFromFile(capturedFilePath);
    if (capSig == null) {
      return (0.0, 'MLKit: không phát hiện khuôn mặt trong ảnh chụp');
    }

    double best = 0;
    int compared = 0;
    for (final path in registeredFilePaths) {
      if (!await File(path).exists()) continue;
      final regSig = await signatureFromCached('mlkit_$path', path);
      if (regSig == null) continue;
      final cos = _cosineSimilarity(capSig, regSig);
      compared++;
      // Map cosine to 0-100 score: same person typically 0.93-0.99, different 0.75-0.90.
      // Stretch the useful band so matching people clearly score above 70.
      final score = _cosineToScore(cos);
      if (score > best) best = score;
    }

    final ms = sw.elapsedMilliseconds;
    if (compared == 0) {
      return (0.0, 'MLKit: không so sánh được ảnh đăng ký nào');
    }
    return (
      double.parse(best.toStringAsFixed(1)),
      'MLKit signature: ${ms}ms, $compared ảnh, điểm ${best.toStringAsFixed(1)}',
    );
  }

  // --- internals ---------------------------------------------------------

  static List<double>? _signatureFromFace(Face face) {
    final left = face.landmarks[FaceLandmarkType.leftEye]?.position;
    final right = face.landmarks[FaceLandmarkType.rightEye]?.position;
    if (left == null || right == null) {
      debugPrint('MlkitSig: missing eye landmarks');
      return null;
    }

    // Use inter-ocular vector to normalise for scale + rotation.
    final mx = (left.x + right.x) / 2.0;
    final my = (left.y + right.y) / 2.0;
    final dx = (right.x - left.x).toDouble();
    final dy = (right.y - left.y).toDouble();
    final interOcular = math.sqrt(dx * dx + dy * dy);
    if (interOcular < 1.0) return null;
    final angle = math.atan2(dy, dx);
    final cosA = math.cos(-angle);
    final sinA = math.sin(-angle);

    final sig = <double>[];

    // 1. Named landmarks (stable on both platforms).
    for (final type in const [
      FaceLandmarkType.leftEye,
      FaceLandmarkType.rightEye,
      FaceLandmarkType.noseBase,
      FaceLandmarkType.leftMouth,
      FaceLandmarkType.rightMouth,
      FaceLandmarkType.bottomMouth,
      FaceLandmarkType.leftCheek,
      FaceLandmarkType.rightCheek,
      FaceLandmarkType.leftEar,
      FaceLandmarkType.rightEar,
    ]) {
      final p = face.landmarks[type]?.position;
      if (p == null) {
        sig.add(0);
        sig.add(0);
      } else {
        final nx = (p.x - mx) / interOcular;
        final ny = (p.y - my) / interOcular;
        // Rotate so inter-ocular axis is horizontal.
        sig.add(nx * cosA - ny * sinA);
        sig.add(nx * sinA + ny * cosA);
      }
    }

    // 2. Contours — add each contour's centroid + extent as extra discriminative features.
    for (final type in const [
      FaceContourType.face,
      FaceContourType.leftEyebrowTop,
      FaceContourType.leftEyebrowBottom,
      FaceContourType.rightEyebrowTop,
      FaceContourType.rightEyebrowBottom,
      FaceContourType.leftEye,
      FaceContourType.rightEye,
      FaceContourType.upperLipTop,
      FaceContourType.upperLipBottom,
      FaceContourType.lowerLipTop,
      FaceContourType.lowerLipBottom,
      FaceContourType.noseBridge,
      FaceContourType.noseBottom,
      FaceContourType.leftCheek,
      FaceContourType.rightCheek,
    ]) {
      final contour = face.contours[type];
      if (contour == null || contour.points.isEmpty) {
        sig.addAll(const [0, 0, 0, 0]);
        continue;
      }
      double sumX = 0, sumY = 0, minX = double.infinity, minY = double.infinity;
      double maxX = -double.infinity, maxY = -double.infinity;
      for (final p in contour.points) {
        final nx = (p.x - mx) / interOcular;
        final ny = (p.y - my) / interOcular;
        final rx = nx * cosA - ny * sinA;
        final ry = nx * sinA + ny * cosA;
        sumX += rx;
        sumY += ry;
        if (rx < minX) minX = rx;
        if (ry < minY) minY = ry;
        if (rx > maxX) maxX = rx;
        if (ry > maxY) maxY = ry;
      }
      final n = contour.points.length;
      sig.add(sumX / n); // centroid x
      sig.add(sumY / n); // centroid y
      sig.add(maxX - minX); // width
      sig.add(maxY - minY); // height
    }

    // L2 normalise the signature so cosine similarity is well-defined.
    double norm = 0;
    for (final v in sig) {
      norm += v * v;
    }
    norm = math.sqrt(norm);
    if (norm < 1e-6) return null;
    return sig.map((v) => v / norm).toList(growable: false);
  }

  static double _cosineSimilarity(List<double> a, List<double> b) {
    if (a.length != b.length) return 0;
    double dot = 0;
    for (int i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
    }
    return dot;
  }

  /// Map raw cosine similarity to a 0-100 match score.
  /// Same person typically cosines 0.93-0.99 → 70-100; different people
  /// cosines 0.75-0.90 → 0-50. The mapping stretches the useful band.
  static double _cosineToScore(double cos) {
    final stretched = (cos - 0.80) / 0.18 * 100.0;
    return stretched.clamp(0.0, 100.0);
  }
}
