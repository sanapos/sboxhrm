import 'dart:async';
import 'package:flutter/foundation.dart';
import '../utils/mobile_device_id.dart';
import '../utils/platform_geolocation.dart';
import 'api_service.dart';

/// GPS định kỳ khi NV được bật chấm ngoài CT — quản lý thấy vị trí realtime trên bản đồ.
class GlobalLocationReporter {
  GlobalLocationReporter._();
  static final GlobalLocationReporter instance = GlobalLocationReporter._();

  final ApiService _api = ApiService();
  Timer? _timer;
  bool _running = false;
  static const _reportInterval = Duration(seconds: 30);

  bool _parseBool(dynamic value) {
    if (value == null) return false;
    if (value is bool) return value;
    if (value is num) return value != 0;
    final s = value.toString().trim().toLowerCase();
    return s == 'true' || s == '1';
  }

  /// Chỉ chạy khi thiết bị đã duyệt và được bật chấm ngoài CT.
  Future<void> startIfEligible({String? employeeId}) async {
    if (kIsWeb) return;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final deviceId = await MobileDeviceId.resolve();
        final resp = await _api.getMyDeviceStatus(
          employeeId: employeeId,
          currentDeviceId: deviceId,
        );
        if (resp['isSuccess'] != true || resp['data'] is! Map) {
          if (attempt < 2) {
            await Future<void>.delayed(const Duration(seconds: 2));
            continue;
          }
          return;
        }
        final data = resp['data'] as Map;
        final approved = _parseBool(data['approved']);
        final allowOutside = _parseBool(data['allowOutsideCheckIn']);
        if (!approved || !allowOutside) {
          debugPrint(
              '📍 GlobalLocationReporter: skip (chưa bật chấm ngoài CT hoặc chưa duyệt thiết bị)');
          stop();
          return;
        }
        start(interval: _reportInterval);
        return;
      } catch (e) {
        debugPrint(
            '📍 GlobalLocationReporter: eligibility check failed (attempt ${attempt + 1}): $e');
        if (attempt < 2) {
          await Future<void>.delayed(const Duration(seconds: 2));
        }
      }
    }
  }

  /// Gọi khi app resume — khởi động lại reporter và gửi GPS ngay (không chờ chu kỳ 30s).
  Future<void> resume({String? employeeId}) async {
    await startIfEligible(employeeId: employeeId);
    if (_running) {
      await _reportWithRetry();
    }
  }

  void start({Duration interval = _reportInterval}) {
    _timer?.cancel();
    _running = true;
    debugPrint(
        '📍 GlobalLocationReporter: started (every ${interval.inSeconds}s)');
    unawaited(_reportWithRetry());
    _timer = Timer.periodic(interval, (_) => _reportWithRetry());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _running = false;
    debugPrint('📍 GlobalLocationReporter: stopped');
  }

  Future<void> _reportWithRetry() async {
    const delays = [Duration.zero, Duration(seconds: 3), Duration(seconds: 8)];
    for (final delay in delays) {
      if (delay > Duration.zero) await Future<void>.delayed(delay);
      if (await _reportOnce()) return;
    }
  }

  Future<bool> _reportOnce() async {
    try {
      if (!kIsWeb) {
        final ok = await ensureLocationPermission();
        if (!ok) {
          debugPrint('📍 GlobalLocationReporter: no location permission');
          return false;
        }
      }
      var pos = await getLastKnownPosition();
      pos ??= await getCurrentPosition(timeout: 15000);
      final resp = await _api.reportLocation(
        latitude: pos.latitude,
        longitude: pos.longitude,
        accuracy: pos.accuracy,
      );
      if (resp['isSuccess'] == true && resp['data'] is Map) {
        final data = resp['data'] as Map;
        final stored = _parseBool(data['stored']);
        if (!stored) {
          final reason = data['reason']?.toString() ?? 'unknown';
          debugPrint('📍 GlobalLocationReporter: server skipped store ($reason)');
          return false;
        }
        debugPrint('📍 GlobalLocationReporter: stored ok');
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('📍 GlobalLocationReporter: report failed: $e');
      return false;
    }
  }
}
