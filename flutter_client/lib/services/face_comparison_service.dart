import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// On-device face comparison service using feature-level algorithms.
/// Uses HOG (Histogram of Oriented Gradients) + dHash (Perceptual Hash) +
/// Histogram similarity — all feature-level, NOT pixel-level.
///
/// Pixel-level methods (NCC, SSIM) fail because a 2-pixel face shift kills
/// the score. Feature-level methods aggregate over regions/cells, making them
/// inherently robust to small position and expression changes.
class FaceComparisonService {
  static const int _compareSize = 128; // 128x128 — more facial detail for discrimination
  static const int _hogCellSize = 8;   // HOG cell size (16x16 cells at 128px)
  static const int _hogBins = 9;       // HOG orientation bins
  static const int _lbpRadius = 1;     // LBP sampling radius
  static const int _lbpGridSize = 8;   // LBP spatial grid (8x8 for fine-grained position)

  /// Compare captured face against registered faces. Returns (score 0-100, details).
  static Future<(double score, String details)> compare(
    Uint8List capturedImageBytes,
    List<String> registeredImagePaths,
  ) async {
    if (registeredImagePaths.isEmpty) {
      return (0.0, 'Không có ảnh đăng ký');
    }

    try {
      final capturedImg = await compute(_decodeAndPreprocess, capturedImageBytes);
      if (capturedImg == null) {
        return (0.0, 'Không xử lý được ảnh chụp');
      }

      double bestScore = 0;
      int compared = 0;

      for (final regPath in registeredImagePaths) {
        try {
          final regFile = File(regPath);
          if (!await regFile.exists()) continue;

          final regBytes = await regFile.readAsBytes();
          final regImg = await compute(_decodeAndPreprocess, regBytes);
          if (regImg == null) continue;

          final score = _compareImages(capturedImg, regImg);
          compared++;
          debugPrint('Face compare [$compared]: score=${score.toStringAsFixed(1)}');

          if (score > bestScore) bestScore = score;
        } catch (e) {
          debugPrint('Error comparing with $regPath: $e');
        }
      }

      if (compared == 0) return (0.0, 'Không so sánh được ảnh nào');

      return (
        double.parse(bestScore.toStringAsFixed(1)),
        'So sánh $compared ảnh, điểm: ${bestScore.toStringAsFixed(1)}'
      );
    } catch (e) {
      debugPrint('Face comparison error: $e');
      return (0.0, 'Lỗi: $e');
    }
  }

  /// Compare pre-cropped face byte arrays (ML Kit face-cropped).
  /// More accurate than [compare] because faces are already isolated.
  static Future<(double score, String details)> compareAllBytes(
    Uint8List capturedBytes,
    List<Uint8List> registeredBytesList,
  ) async {
    if (registeredBytesList.isEmpty) {
      return (0.0, 'Không có ảnh đăng ký');
    }

    try {
      final capturedImg = await compute(_decodeAndPreprocess, capturedBytes);
      if (capturedImg == null) {
        return (0.0, 'Không xử lý được ảnh chụp');
      }

      double bestScore = 0;
      int compared = 0;

      for (final regBytes in registeredBytesList) {
        try {
          final regImg = await compute(_decodeAndPreprocess, regBytes);
          if (regImg == null) continue;

          final score = _compareImages(capturedImg, regImg);
          compared++;
          debugPrint('Face compare [$compared]: score=${score.toStringAsFixed(1)}');

          if (score > bestScore) bestScore = score;
        } catch (e) {
          debugPrint('Error comparing: $e');
        }
      }

      if (compared == 0) return (0.0, 'Không so sánh được ảnh nào');

      return (
        double.parse(bestScore.toStringAsFixed(1)),
        'So sánh $compared ảnh, điểm: ${bestScore.toStringAsFixed(1)}'
      );
    } catch (e) {
      debugPrint('Face comparison error: $e');
      return (0.0, 'Lỗi: $e');
    }
  }

  /// Preprocess: EXIF → square crop → face-focus center 60% → 128x128 grayscale
  /// → brightness normalize.
  static _PreprocessedImage? _decodeAndPreprocess(Uint8List bytes) {
    try {
      var image = img.decodeImage(bytes);
      if (image == null) return null;

      image = img.bakeOrientation(image);

      // Square crop
      final minDim = math.min(image.width, image.height);
      final cropX = (image.width - minDim) ~/ 2;
      final cropY = (image.height - minDim) ~/ 2;
      var processed = img.copyCrop(image,
          x: cropX, y: cropY, width: minDim, height: minDim);

      // Face-focused: center 60% (was 50% — slightly larger to include jawline)
      final faceDim = (processed.width * 0.60).round();
      final faceOffset = (processed.width - faceDim) ~/ 2;
      processed = img.copyCrop(processed,
          x: faceOffset, y: faceOffset, width: faceDim, height: faceDim);

      // Resize to 64x64
      processed = img.copyResize(processed,
          width: _compareSize, height: _compareSize,
          interpolation: img.Interpolation.linear);

      processed = img.grayscale(processed);
      // NO blur — at 128x128, blur destroys discriminative facial detail

      // Extract pixels
      final pixels = Float64List(_compareSize * _compareSize);
      for (int y = 0; y < _compareSize; y++) {
        for (int x = 0; x < _compareSize; x++) {
          pixels[y * _compareSize + x] = processed.getPixel(x, y).r.toDouble();
        }
      }

      // Brightness normalization (stretch to 0-255)
      double lo = 255, hi = 0;
      for (int i = 0; i < pixels.length; i++) {
        if (pixels[i] < lo) lo = pixels[i];
        if (pixels[i] > hi) hi = pixels[i];
      }
      final range = hi - lo;
      if (range > 10) {
        for (int i = 0; i < pixels.length; i++) {
          pixels[i] = ((pixels[i] - lo) / range) * 255.0;
        }
      }

      return _PreprocessedImage(pixels, _compareSize, _compareSize);
    } catch (e) {
      return null;
    }
  }

  // ======================== COMPARISON ========================

  /// Feature-level comparison: HOG 30% + LBP 30% + dHash 20% + Histogram 20%.
  /// NO pixel-level methods — all aggregate over regions/cells.
  static double _compareImages(_PreprocessedImage a, _PreprocessedImage b) {
    // 1. HOG: Histogram of Oriented Gradients (face shape structure)
    final hogA = _computeHOG(a);
    final hogB = _computeHOG(b);
    final hogSim = _cosineSimilarity(hogA, hogB);

    // 2. LBP: Local Binary Pattern (face TEXTURE — #1 for face recognition)
    final lbpA = _computeLBP(a);
    final lbpB = _computeLBP(b);
    final lbpSim = _histogramSimilarity(lbpA, lbpB);

    // 3. dHash: Perceptual hash (extremely robust to small changes)
    final hashA = _computeDHash(a);
    final hashB = _computeDHash(b);
    final dHashSim = _hashSimilarity(hashA, hashB);

    // 4. Histogram: brightness distribution
    final histA = _computeHistogram(a);
    final histB = _computeHistogram(b);
    final histSim = _histogramSimilarity(histA, histB);

    // Weights: prioritize identity-discriminative features (LBP, HOG)
    // Histogram & dHash are supplementary (not identity-specific)
    final rawScore = (hogSim * 0.35 + lbpSim * 0.40 + dHashSim * 0.15 + histSim * 0.10) * 100.0;

    // Penalty gate: if BOTH primary features score low, very likely different person
    double score;
    if (hogSim < 0.40 && lbpSim < 0.40) {
      score = rawScore * 0.7; // Both primary features disagree → penalize
    } else {
      score = rawScore;
    }

    debugPrint('  HOG=${(hogSim * 100).toStringAsFixed(1)} '
        'LBP=${(lbpSim * 100).toStringAsFixed(1)} '
        'dHash=${(dHashSim * 100).toStringAsFixed(1)} '
        'Hist=${(histSim * 100).toStringAsFixed(1)} '
        'Raw=${rawScore.toStringAsFixed(1)} '
        'Final=${score.toStringAsFixed(1)}');

    return score;
  }

  // ======================== HOG ========================

  /// Compute HOG (Histogram of Oriented Gradients) feature vector.
  /// Divides image into 8x8 cells, computes 9-bin gradient orientation
  /// histogram per cell, normalizes across 2x2 blocks.
  /// This is the standard pre-deep-learning face feature used by dlib/OpenCV.
  static Float64List _computeHOG(_PreprocessedImage image) {
    final w = image.width;
    final h = image.height;
    final cellsX = w ~/ _hogCellSize;
    final cellsY = h ~/ _hogCellSize;

    // Step 1: Compute gradient magnitude and orientation for each pixel
    final magMap = Float64List(w * h);
    final oriMap = Float64List(w * h);

    for (int y = 1; y < h - 1; y++) {
      for (int x = 1; x < w - 1; x++) {
        final gx = image.at(x + 1, y) - image.at(x - 1, y);
        final gy = image.at(x, y + 1) - image.at(x, y - 1);
        magMap[y * w + x] = math.sqrt(gx * gx + gy * gy);
        // Orientation 0-180 (unsigned gradient — face edges have no preferred direction)
        var angle = math.atan2(gy, gx) * 180.0 / math.pi;
        if (angle < 0) angle += 180.0;
        oriMap[y * w + x] = angle;
      }
    }

    // Step 2: Compute histogram per cell (9 bins, 0-180°, bilinear vote)
    final cellHists = List.generate(
        cellsY, (_) => List.generate(cellsX, (_) => Float64List(_hogBins)));

    for (int cy = 0; cy < cellsY; cy++) {
      for (int cx = 0; cx < cellsX; cx++) {
        final hist = cellHists[cy][cx];
        for (int dy = 0; dy < _hogCellSize; dy++) {
          for (int dx = 0; dx < _hogCellSize; dx++) {
            final px = cx * _hogCellSize + dx;
            final py = cy * _hogCellSize + dy;
            if (px >= w || py >= h) continue;

            final mag = magMap[py * w + px];
            final ori = oriMap[py * w + px];

            // Bilinear interpolation between bins
            final binF = ori / 20.0; // 180° / 9 bins = 20° per bin
            final bin0 = binF.floor() % _hogBins;
            final bin1 = (bin0 + 1) % _hogBins;
            final frac = binF - binF.floor();

            hist[bin0] += mag * (1.0 - frac);
            hist[bin1] += mag * frac;
          }
        }
      }
    }

    // Step 3: Normalize across 2x2 cell blocks (L2-norm) → feature vector
    final blocksX = cellsX - 1;
    final blocksY = cellsY - 1;
    if (blocksX <= 0 || blocksY <= 0) return Float64List(0);

    final featureLen = blocksX * blocksY * 4 * _hogBins;
    final features = Float64List(featureLen);
    int idx = 0;

    for (int by = 0; by < blocksY; by++) {
      for (int bx = 0; bx < blocksX; bx++) {
        // Collect 4 cell histograms in this 2x2 block
        final block = Float64List(4 * _hogBins);
        for (int dy = 0; dy < 2; dy++) {
          for (int dx = 0; dx < 2; dx++) {
            final src = cellHists[by + dy][bx + dx];
            final offset = (dy * 2 + dx) * _hogBins;
            for (int b = 0; b < _hogBins; b++) {
              block[offset + b] = src[b];
            }
          }
        }

        // L2 normalize
        double norm = 0;
        for (int i = 0; i < block.length; i++) norm += block[i] * block[i];
        norm = math.sqrt(norm) + 1e-6;

        for (int i = 0; i < block.length; i++) {
          features[idx++] = block[i] / norm;
        }
      }
    }

    return Float64List.sublistView(features, 0, idx);
  }

  // ======================== LBP (Local Binary Pattern) ========================

  /// Compute LBP histogram — THE standard face texture descriptor.
  /// For each pixel, compare with 8 neighbors. If neighbor >= center, bit=1.
  /// Produces an 8-bit code (0-255) per pixel. Histogram over spatial regions
  /// captures texture patterns (eyes, nose, mouth contours) that are
  /// consistent for the same person regardless of lighting/position.
  /// Uses grid-based spatial histogram (4x4 grid) for position sensitivity.
  static Float64List _computeLBP(_PreprocessedImage image) {
    final w = image.width;
    final h = image.height;
    final gridSize = _lbpGridSize; // 8x8 spatial grid for fine-grained position
    const bins = 59; // 58 uniform patterns + 1 non-uniform bin
    final regionW = w ~/ gridSize;
    final regionH = h ~/ gridSize;

    // 8-neighbor offsets (clockwise from top-left)
    const dx = [-1, 0, 1, 1, 1, 0, -1, -1];
    const dy = [-1, -1, -1, 0, 1, 1, 1, 0];

    // Build uniform pattern lookup (patterns with <=2 bit transitions)
    final uniformMap = Int32List(256);
    int uniformIdx = 0;
    for (int i = 0; i < 256; i++) {
      int transitions = 0;
      for (int b = 0; b < 8; b++) {
        final bit1 = (i >> b) & 1;
        final bit2 = (i >> ((b + 1) % 8)) & 1;
        if (bit1 != bit2) transitions++;
      }
      if (transitions <= 2) {
        uniformMap[i] = uniformIdx++;
      } else {
        uniformMap[i] = bins - 1; // non-uniform → last bin
      }
    }

    final totalBins = gridSize * gridSize * bins;
    final histogram = Float64List(totalBins);

    for (int gy = 0; gy < gridSize; gy++) {
      for (int gx = 0; gx < gridSize; gx++) {
        final regionOffset = (gy * gridSize + gx) * bins;
        int count = 0;

        final startX = gx * regionW + _lbpRadius;
        final endX = math.min((gx + 1) * regionW, w - _lbpRadius);
        final startY = gy * regionH + _lbpRadius;
        final endY = math.min((gy + 1) * regionH, h - _lbpRadius);

        for (int y = startY; y < endY; y++) {
          for (int x = startX; x < endX; x++) {
            final center = image.at(x, y);
            int code = 0;
            for (int n = 0; n < 8; n++) {
              if (image.at(x + dx[n], y + dy[n]) >= center) {
                code |= (1 << n);
              }
            }
            histogram[regionOffset + uniformMap[code]]++;
            count++;
          }
        }

        // Normalize this region's histogram
        if (count > 0) {
          for (int b = 0; b < bins; b++) {
            histogram[regionOffset + b] /= count;
          }
        }
      }
    }

    return histogram;
  }

  // ======================== dHash (Perceptual Hash) ========================

  /// Compute difference hash (dHash) — 256-bit perceptual fingerprint.
  /// Resizes to 17x16, computes horizontal gradient direction → 256-bit hash.
  /// Higher resolution than standard 64-bit for better face discrimination.
  static Int32List _computeDHash(_PreprocessedImage image) {
    // Downsample to 17x16 by averaging blocks
    const dw = 17, dh = 16;
    final small = Float64List(dw * dh);
    final bw = image.width / dw;
    final bh = image.height / dh;

    for (int sy = 0; sy < dh; sy++) {
      for (int sx = 0; sx < dw; sx++) {
        double sum = 0;
        int count = 0;
        final startX = (sx * bw).floor();
        final endX = ((sx + 1) * bw).ceil().clamp(0, image.width);
        final startY = (sy * bh).floor();
        final endY = ((sy + 1) * bh).ceil().clamp(0, image.height);

        for (int y = startY; y < endY; y++) {
          for (int x = startX; x < endX; x++) {
            if (x < image.width && y < image.height) {
              sum += image.at(x, y);
              count++;
            }
          }
        }
        small[sy * dw + sx] = count > 0 ? sum / count : 0;
      }
    }

    // Compare adjacent horizontal pixels → 256-bit hash
    final hash = Int32List(dh * (dw - 1)); // 16 * 16 = 256 bits
    int idx = 0;
    for (int y = 0; y < dh; y++) {
      for (int x = 0; x < dw - 1; x++) {
        hash[idx++] = small[y * dw + x] < small[y * dw + x + 1] ? 1 : 0;
      }
    }
    return Int32List.sublistView(hash, 0, idx);
  }

  /// Hash similarity: 1 - (hamming distance / bits). Returns 0-1.
  static double _hashSimilarity(Int32List a, Int32List b) {
    if (a.length != b.length || a.isEmpty) return 0;
    int same = 0;
    for (int i = 0; i < a.length; i++) {
      if (a[i] == b[i]) same++;
    }
    return same / a.length;
  }

  // ======================== Histogram ========================

  /// 32-bin normalized brightness histogram.
  static Float64List _computeHistogram(_PreprocessedImage image) {
    final histogram = Float64List(32);
    final total = image.pixels.length;

    for (int i = 0; i < total; i++) {
      var bin = (image.pixels[i] / 8).floor();
      if (bin >= 32) bin = 31;
      if (bin < 0) bin = 0;
      histogram[bin]++;
    }

    for (int i = 0; i < 32; i++) histogram[i] /= total;
    return histogram;
  }

  /// Bhattacharyya histogram similarity. Returns 0-1.
  static double _histogramSimilarity(Float64List a, Float64List b) {
    if (a.length != b.length) return 0;
    double sum = 0;
    for (int i = 0; i < a.length; i++) {
      sum += math.sqrt(a[i] * b[i]);
    }
    return sum;
  }

  // ======================== Common ========================

  /// Cosine similarity. Returns 0-1.
  static double _cosineSimilarity(Float64List a, Float64List b) {
    if (a.length != b.length || a.isEmpty) return 0;
    double dot = 0, magA = 0, magB = 0;
    for (int i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      magA += a[i] * a[i];
      magB += b[i] * b[i];
    }
    if (magA == 0 || magB == 0) return 0;
    return math.max(0, dot / (math.sqrt(magA) * math.sqrt(magB)));
  }
}

/// Preprocessed grayscale image.
class _PreprocessedImage {
  final Float64List pixels;
  final int width;
  final int height;

  _PreprocessedImage(this.pixels, this.width, this.height);

  double at(int x, int y) => pixels[y * width + x];
}
