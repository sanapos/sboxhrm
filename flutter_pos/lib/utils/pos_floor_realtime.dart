import 'dart:async';

import '../services/signalr_service.dart';

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
