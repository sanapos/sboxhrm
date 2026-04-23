// ios_native_face_embedder.dart
//
// Thin wrapper around the iOS-native CoreML + Vision face embedder exposed
// by flutter_client/ios/Runner/NativeFaceEmbedder.swift via the
// MethodChannel 'sana/native_face_embedder'.
//
// On non-iOS platforms every method is a no-op and `isAvailable` returns
// false, so callers can fall back to the TFLite or HOG+LBP paths.

import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class IosNativeFaceEmbedder {
  static const MethodChannel _channel =
      MethodChannel('sana/native_face_embedder');

  static bool _probed = false;
  static bool _available = false;

  /// One-time probe: does the iOS side respond to `isReady`?
  /// Returns `false` immediately on non-iOS or when the channel is missing.
  static Future<bool> isAvailable() async {
    if (kIsWeb || !Platform.isIOS) return false;
    if (_probed) return _available;
    try {
      final ready = await _channel.invokeMethod<bool>('isReady');
      _available = ready == true;
    } catch (e) {
      debugPrint('IosNativeFaceEmbedder probe failed: $e');
      _available = false;
    }
    _probed = true;
    return _available;
  }

  /// Forces a re-probe next time (e.g. after the user updates the app).
  static void reset() {
    _probed = false;
    _available = false;
  }

  /// Embed [imageBytes] (JPEG/PNG, face already visible) into a 512-dim
  /// L2-normalized Float32 vector. Returns null on failure.
  static Future<Float32List?> embed(Uint8List imageBytes) async {
    if (!await isAvailable()) return null;
    try {
      final result = await _channel.invokeMethod<Uint8List>('embed', {
        'bytes': imageBytes,
      });
      if (result == null || result.lengthInBytes < 4) return null;
      return Float32List.view(
        result.buffer,
        result.offsetInBytes,
        result.lengthInBytes ~/ 4,
      );
    } catch (e) {
      debugPrint('IosNativeFaceEmbedder.embed error: $e');
      return null;
    }
  }

  /// Compare two Float32 embeddings via the native helper. Both must be
  /// produced by [embed] so they share the same L2 norm convention.
  /// Returns a 0..100 cosine score.
  static Future<double> compareRaw(Float32List a, Float32List b) async {
    if (!await isAvailable()) return 0.0;
    try {
      final score = await _channel.invokeMethod<double>('compareRaw', {
        'a': a.buffer.asUint8List(a.offsetInBytes, a.lengthInBytes),
        'b': b.buffer.asUint8List(b.offsetInBytes, b.lengthInBytes),
      });
      return score ?? 0.0;
    } catch (e) {
      debugPrint('IosNativeFaceEmbedder.compareRaw error: $e');
      return 0.0;
    }
  }
}
