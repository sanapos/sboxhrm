import 'dart:async';
import 'package:flutter/foundation.dart';
import '../utils/platform_geolocation.dart';
import 'api_service.dart';

/// Global periodic GPS reporter. Starts when user logs in and runs until logout,
/// so managers can see real-time employee positions on the map regardless of
/// which screen the employee is currently on.
class GlobalLocationReporter {
  GlobalLocationReporter._();
  static final GlobalLocationReporter instance = GlobalLocationReporter._();

  final ApiService _api = ApiService();
  Timer? _timer;
  bool _running = false;

  /// Start periodic reporting every [interval]. Safe to call multiple times.
  void start({Duration interval = const Duration(seconds: 90)}) {
    if (_running) return;
    _running = true;
    debugPrint('📍 GlobalLocationReporter: started (every ${interval.inSeconds}s)');
    // Fire immediately, then on a schedule.
    _reportOnce();
    _timer = Timer.periodic(interval, (_) => _reportOnce());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _running = false;
    debugPrint('📍 GlobalLocationReporter: stopped');
  }

  Future<void> _reportOnce() async {
    try {
      if (!kIsWeb) {
        final ok = await ensureLocationPermission();
        if (!ok) return;
      }
      final pos = await getCurrentPosition();
      await _api.reportLocation(
        latitude: pos.latitude,
        longitude: pos.longitude,
        accuracy: pos.accuracy,
      );
    } catch (e) {
      debugPrint('📍 GlobalLocationReporter: report failed: $e');
    }
  }
}
