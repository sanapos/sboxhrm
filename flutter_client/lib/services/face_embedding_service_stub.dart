import 'dart:typed_data';
import 'package:flutter/foundation.dart';

/// Web stub for FaceEmbeddingService.
/// TFLite is not supported on web — face comparison is done server-side.
class FaceEmbeddingService {
  static Future<void> initialize() async {
    debugPrint('FaceEmbeddingService: not available on web (TFLite unsupported)');
  }

  static bool get isReady => false;

  static Future<Float32List?> getEmbedding(Uint8List imageBytes) async => null;

  static double compareFaces(Float32List embedding1, Float32List embedding2) => 0;

  static Future<Float32List?> getEmbeddingCached(String key, Uint8List imageBytes) async => null;

  static void clearCache() {}

  static Future<(double score, String details)> compareWithCachedRegistered(
    Uint8List capturedBytes,
    List<String> registeredKeys,
    List<Uint8List> registeredBytesList,
  ) async {
    return (0.0, 'Web: server-side comparison');
  }

  static Future<(double score, String details)> compareAllBytes(
    Uint8List capturedBytes,
    List<Uint8List> registeredBytesList,
  ) async {
    return (0.0, 'Web: server-side comparison');
  }

  static void dispose() {}
}
