import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// Đo thời gian từng bước thao tác bán hàng (thêm món, báo bếp, thanh toán, in bill) — ghi logcat
/// dạng «⏱ checkout shift=0 stock=420 pay=380 total=830ms» để tìm chỗ chậm trên máy thật.
class PosPerf {
  PosPerf(this.name) : _sw = Stopwatch()..start();

  final String name;
  final Stopwatch _sw;
  int _last = 0;
  final List<String> _parts = [];
  bool _done = false;

  int get elapsedMs => _sw.elapsedMilliseconds;

  void mark(String step) {
    final t = _sw.elapsedMilliseconds;
    _parts.add('$step=${t - _last}');
    _last = t;
  }

  void done([String extra = '']) {
    if (_done) return;
    _done = true;
    debugPrint('⏱ $name ${_parts.join(' ')} total=${_sw.elapsedMilliseconds}ms $extra'.trim());
  }

  static bool _framesHooked = false;

  /// Ghi các khung hình > [thresholdMs] (build + vẽ) — bấm thấy «khựng» thường do khung hình dài.
  static void watchSlowFrames({int thresholdMs = 100}) {
    if (_framesHooked) return;
    _framesHooked = true;
    SchedulerBinding.instance.addTimingsCallback((timings) {
      for (final t in timings) {
        final total = t.totalSpan.inMilliseconds;
        if (total < thresholdMs) continue;
        debugPrint('⏱ slow frame total=${total}ms build=${t.buildDuration.inMilliseconds}ms '
            'raster=${t.rasterDuration.inMilliseconds}ms');
      }
    });
  }
}
