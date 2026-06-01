import 'package:flutter/foundation.dart';
import '../services/api_service.dart';
import 'device_sync_progress_overlay.dart';

export 'device_sync_types.dart';

/// Khởi chạy tải dữ liệu — panel góc dưới màn hình (xem [DeviceSyncProgressOverlay]).
class DeviceSyncProgressDialog {
  DeviceSyncProgressDialog._();

  static Future<List<DeviceSyncProgressResult>> show({
    required ApiService apiService,
    required DeviceSyncKind kind,
    required List<DeviceSyncTarget> devices,
    VoidCallback? onDataReady,
  }) {
    return DeviceSyncProgressManager.instance.startSync(
      apiService: apiService,
      kind: kind,
      devices: devices,
      onDataReady: onDataReady,
    );
  }
}
