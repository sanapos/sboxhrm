// dart:io used conditionally on mobile platforms
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

/// Face embedding service using MobileFaceNet (TFLite).
/// Converts face images to 192-dimensional identity vectors.
/// Cosine similarity between vectors determines if two faces are the same person.
///
/// This is the same technology used by FaceID, ZKTeco face machines, etc.
/// Unlike HOG/LBP/dHash which compare images, this compares IDENTITY.
class FaceEmbeddingService {
  static Interpreter? _interpreter;
  static const int _inputSize = 112; // MobileFaceNet input: 112x112
  static int _embeddingSize = 192; // Output dimension (will be read from model)

  // Cache: path → embedding (avoids recomputing for registered faces)
  static final Map<String, Float32List> _embeddingCache = {};

  /// Initialize the TFLite interpreter (call once on app start or first use).
  static Future<void> initialize() async {
    if (_interpreter != null) return;

    try {
      _interpreter = await Interpreter.fromAsset('assets/mobilefacenet.tflite');
      debugPrint('MobileFaceNet loaded successfully');

      final inputTensors = _interpreter!.getInputTensors();
      final outputTensors = _interpreter!.getOutputTensors();
      final inputShape = inputTensors.first.shape;
      final outputShape = outputTensors.first.shape;
      debugPrint('Input: $inputShape ${inputTensors.first.type}');
      debugPrint('Output: $outputShape ${outputTensors.first.type}');
      
      // Dynamically set embedding size from model
      _embeddingSize = outputShape.last;
      debugPrint('Embedding size: $_embeddingSize');
    } catch (e) {
      debugPrint('Failed to load MobileFaceNet: $e');
      _interpreter = null;
    }
  }

  /// Check if the model is loaded and ready.
  static bool get isReady => _interpreter != null;

  /// Get face embedding (192-dim vector) from image bytes.
  /// The image should be face-cropped (from ML Kit bounding box).
  static Future<Float32List?> getEmbedding(Uint8List imageBytes) async {
    if (_interpreter == null) {
      await initialize();
      if (_interpreter == null) {
        debugPrint('FaceNet: interpreter is null, cannot get embedding');
        return null;
      }
    }

    try {
      // Preprocess in isolate to avoid jank
      final inputFlat = await compute(_preprocessImageFlat, imageBytes);
      if (inputFlat == null) {
        debugPrint('FaceNet: preprocess returned null');
        return null;
      }

      // Reshape flat Float32List to [1, 112, 112, 3] nested list for TFLite
      final inputReshaped = inputFlat.toList().reshape<double>([1, _inputSize, _inputSize, 3]);

      // Run inference — output must be List<List<double>>, NOT List<Float32List>
      final output = List.generate(1, (_) => List<double>.filled(_embeddingSize, 0));
      _interpreter!.run(inputReshaped, output);

      // L2 normalize the embedding
      final raw = output[0];
      final embedding = Float32List(_embeddingSize);
      double norm = 0;
      for (int i = 0; i < raw.length; i++) {
        embedding[i] = raw[i].toDouble();
        norm += embedding[i] * embedding[i];
      }
      norm = math.sqrt(norm);
      if (norm > 0) {
        for (int i = 0; i < embedding.length; i++) {
          embedding[i] /= norm;
        }
      }

      debugPrint('FaceNet: embedding OK, norm=${norm.toStringAsFixed(3)}, '
          'first3=[${embedding[0].toStringAsFixed(4)}, ${embedding[1].toStringAsFixed(4)}, ${embedding[2].toStringAsFixed(4)}]');

      return embedding;
    } catch (e, stack) {
      debugPrint('Face embedding error: $e');
      debugPrint('Stack: ${stack.toString().split('\n').take(5).join('\n')}');
      return null;
    }
  }

  /// Preprocess image for MobileFaceNet: decode → crop square → resize 112x112 → RGB float32 [-1,1].
  /// Returns flat Float32List of size 112*112*3 for TFLite input.
  static Float32List? _preprocessImageFlat(Uint8List bytes) {
    try {
      var image = img.decodeImage(bytes);
      if (image == null) return null;

      image = img.bakeOrientation(image);

      // Square crop (center)
      final minDim = math.min(image.width, image.height);
      final cropX = (image.width - minDim) ~/ 2;
      final cropY = (image.height - minDim) ~/ 2;
      var processed = img.copyCrop(image,
          x: cropX, y: cropY, width: minDim, height: minDim);

      // Resize to 112x112
      processed = img.copyResize(processed,
          width: _inputSize, height: _inputSize,
          interpolation: img.Interpolation.linear);

      // Convert to flat Float32List [112*112*3] normalized to [-1, 1]
      final pixels = Float32List(_inputSize * _inputSize * 3);
      int idx = 0;
      for (int y = 0; y < _inputSize; y++) {
        for (int x = 0; x < _inputSize; x++) {
          final pixel = processed.getPixel(x, y);
          pixels[idx++] = (pixel.r.toDouble() - 127.5) / 127.5;
          pixels[idx++] = (pixel.g.toDouble() - 127.5) / 127.5;
          pixels[idx++] = (pixel.b.toDouble() - 127.5) / 127.5;
        }
      }

      return pixels;
    } catch (e) {
      return null;
    }
  }

  /// Compare two face embeddings using cosine similarity.
  /// Returns 0-100 score. Same person typically scores 70-100, different person 0-40.
  static double compareFaces(Float32List embedding1, Float32List embedding2) {
    if (embedding1.length != embedding2.length) return 0;

    double dot = 0;
    for (int i = 0; i < embedding1.length; i++) {
      dot += embedding1[i] * embedding2[i];
    }
    // Both are L2-normalized, so dot product = cosine similarity [-1, 1]
    // Map to 0-100 score
    final score = ((dot + 1) / 2) * 100;
    return score.clamp(0, 100);
  }

  /// Get cached embedding for a file path, or compute and cache it.
  static Future<Float32List?> getEmbeddingCached(String key, Uint8List imageBytes) async {
    if (_embeddingCache.containsKey(key)) {
      return _embeddingCache[key];
    }
    final emb = await getEmbedding(imageBytes);
    if (emb != null) {
      _embeddingCache[key] = emb;
    }
    return emb;
  }

  /// Clear embedding cache (call when face re-registration happens).
  static void clearCache() {
    _embeddingCache.clear();
  }

  /// Compare captured face bytes against pre-cached registered embeddings.
  /// Much faster than compareAllBytes since registered embeddings are cached.
  static Future<(double score, String details)> compareWithCachedRegistered(
    Uint8List capturedBytes,
    List<String> registeredKeys,
    List<Uint8List> registeredBytesList,
  ) async {
    if (registeredBytesList.isEmpty) {
      return (0.0, 'Kh\u00f4ng c\u00f3 \u1ea3nh \u0111\u0103ng k\u00fd');
    }

    final sw = Stopwatch()..start();
    final capturedEmb = await getEmbedding(capturedBytes);
    final inferMs = sw.elapsedMilliseconds;
    if (capturedEmb == null) {
      return (0.0, 'Kh\u00f4ng tr\u00edch xu\u1ea5t \u0111\u01b0\u1ee3c \u0111\u1eb7c tr\u01b0ng');
    }

    double bestScore = 0;
    int compared = 0;

    for (int i = 0; i < registeredBytesList.length; i++) {
      final key = i < registeredKeys.length ? registeredKeys[i] : 'reg_$i';
      final regEmb = await getEmbeddingCached(key, registeredBytesList[i]);
      if (regEmb == null) continue;

      final score = compareFaces(capturedEmb, regEmb);
      compared++;
      if (score > bestScore) bestScore = score;
    }

    final totalMs = sw.elapsedMilliseconds;
    debugPrint('FaceNet: infer=${inferMs}ms total=${totalMs}ms best=${bestScore.toStringAsFixed(1)} ($compared \u1ea3nh)');

    if (compared == 0) return (0.0, 'Kh\u00f4ng so s\u00e1nh \u0111\u01b0\u1ee3c');

    return (
      double.parse(bestScore.toStringAsFixed(1)),
      'FaceNet: ${totalMs}ms, $compared \u1ea3nh, \u0111i\u1ec3m: ${bestScore.toStringAsFixed(1)}'
    );
  }

  /// Compare captured face bytes against multiple registered face bytes.
  /// Returns (bestScore, details).
  static Future<(double score, String details)> compareAllBytes(
    Uint8List capturedBytes,
    List<Uint8List> registeredBytesList,
  ) async {
    if (registeredBytesList.isEmpty) {
      return (0.0, 'Không có ảnh đăng ký');
    }

    final capturedEmb = await getEmbedding(capturedBytes);
    if (capturedEmb == null) {
      return (0.0, 'Không trích xuất được đặc trưng ảnh chụp');
    }

    double bestScore = 0;
    int compared = 0;

    for (final regBytes in registeredBytesList) {
      final regEmb = await getEmbedding(regBytes);
      if (regEmb == null) continue;

      final score = compareFaces(capturedEmb, regEmb);
      compared++;
      debugPrint('FaceNet compare [$compared]: cosine=${score.toStringAsFixed(1)}');

      if (score > bestScore) bestScore = score;
    }

    if (compared == 0) return (0.0, 'Không so sánh được ảnh nào');

    return (
      double.parse(bestScore.toStringAsFixed(1)),
      'FaceNet: $compared ảnh, điểm: ${bestScore.toStringAsFixed(1)}'
    );
  }

  /// Clean up interpreter resources.
  static void dispose() {
    _interpreter?.close();
    _interpreter = null;
  }
}
