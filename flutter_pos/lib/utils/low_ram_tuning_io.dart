import 'dart:io';

import 'package:flutter/painting.dart';

/// V2s / C20Lite ~3 GB: ImageCache mặc định 100 MB → OOM → Android «đã dừng».
void applyLowRamImageCache() {
  var memMb = 0;
  if (Platform.isAndroid) {
    try {
      for (final line in File('/proc/meminfo').readAsLinesSync()) {
        if (!line.startsWith('MemTotal:')) continue;
        final parts = line.split(RegExp(r'\s+'));
        if (parts.length >= 2) {
          memMb = (int.tryParse(parts[1]) ?? 0) ~/ 1024;
        }
        break;
      }
    } catch (_) {}
  }
  final cache = PaintingBinding.instance.imageCache;
  if (memMb > 0 && memMb <= 4096) {
    cache.maximumSize = 32;
    cache.maximumSizeBytes = 16 << 20;
  } else if (Platform.isAndroid) {
    cache.maximumSize = 80;
    cache.maximumSizeBytes = 48 << 20;
  }
}
