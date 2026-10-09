import 'dart:async';

import '../services/signalr_service.dart';

/// Phân loại lý do của PosFloorChanged — màn nào chỉ xử lý sự kiện liên quan.
abstract final class PosSyncReasons {
  static String of(Map<String, dynamic> e) =>
      (e['reason'] ?? e['Reason'] ?? '').toString().toLowerCase();

  static String? id(Map<String, dynamic> e, String key) {
    final v = (e[key] ?? e[key[0].toUpperCase() + key.substring(1)])?.toString().trim();
    return v == null || v.isEmpty ? null : v.toLowerCase();
  }

  /// Hàng / giá / tồn đổi → máy bán đồng bộ phần thay đổi danh mục.
  static const catalog = {
    'catalogchanged', 'salecompleted', 'salereturned', 'returncancelled', 'saledeleted',
  };

  /// Không liên quan sơ đồ bàn / bếp (chỉ danh mục hoặc HĐ quầy / thiết lập).
  static const notFloor = {'catalogchanged', 'slotsaved', 'settingschanged'};

  /// Thao tác bàn có thể đổi đơn đang mở trên máy này dù id không khớp tab.
  static const floorOps = {
    'transfer', 'merge', 'split', 'splitbill', 'opensession', 'closesession', 'freeresource',
  };
}

/// Debounced listener cho event `PosFloorChanged` (sơ đồ / draft bàn).
class PosFloorRealtimeSubscription {
  PosFloorRealtimeSubscription({
    this.debounce = const Duration(milliseconds: 400),
  });

  final Duration debounce;
  StreamSubscription<Map<String, dynamic>>? _sub;
  Timer? _timer;

  void start(void Function(Map<String, dynamic> event) onChanged) {
    dispose();
    _sub = SignalRService().onPosFloorChanged.listen((event) {
      _timer?.cancel();
      _timer = Timer(debounce, () => onChanged(event));
    });
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
    _sub?.cancel();
    _sub = null;
  }
}
