import 'pos_print_agent_settings.dart';

/// Phân vai in cloud: thiết bị gắn máy in (Agent) vs thiết bị gửi lệnh từ xa.
abstract final class PosPrintRole {
  static String _normId(String id) => id.trim().toLowerCase();

  /// Chuẩn hóa GUID máy in để so khớp (không phân biệt hoa/thường).
  static String normalizePrinterId(String id) => _normId(id);

  /// So khớp GUID máy in (không phân biệt hoa/thường).
  static bool matchesPrinterId(String a, String b) =>
      _normId(a) == _normId(b);

  /// Máy đang bật Print Agent (A6) — được ưu tiên in local.
  /// Máy thu ngân (A7/web) → false: luôn gửi cloud, không thử LAN/USB «ảo».
  static Future<bool> isPrintAgentDevice() async {
    final settings = await PosPrintAgentSettings.load();
    return settings.enabled;
  }

  /// Thiết bị này là Print Agent cho [printerId] (nhận & in cục bộ).
  static Future<bool> isAgentForPrinter(String printerId) async {
    if (printerId.trim().isEmpty) return false;
    final settings = await PosPrintAgentSettings.load();
    if (!settings.enabled) return false;

    final assigned = await assignedPrinterIds();
    final want = _normId(printerId);
    return assigned.any((id) => _normId(id) == want);
  }

  /// Danh sách máy in mà thiết bị này đang phục vụ (Agent).
  static Future<List<String>> assignedPrinterIds() async {
    final settings = await PosPrintAgentSettings.load();
    if (!settings.enabled) return const [];
    return List<String>.from(settings.assignedPrinterIds);
  }
}

/// Job do thiết bị hiện tại gửi lên cloud — Agent không claim lại.
abstract final class PosPrintSessionRegistry {
  static final _outboundJobIds = <String>{};

  static void markOutbound(String jobId) {
    if (jobId.isEmpty) return;
    _outboundJobIds.add(jobId);
    if (_outboundJobIds.length > 100) {
      _outboundJobIds.remove(_outboundJobIds.first);
    }
  }

  static bool isOutbound(String jobId) => _outboundJobIds.contains(jobId);

  static void clearOutbound(String jobId) => _outboundJobIds.remove(jobId);
}

/// Chặn in trùng cùng chứng từ trong cửa sổ ngắn (bấm Hoàn tất nhiều lần).
abstract final class PosPrintDedup {
  static final _recent = <String, DateTime>{};
  static final _inFlightUntil = <String, DateTime>{};
  static const _window = Duration(seconds: 25);
  /// Khóa cứng chống double-tap cùng frame (trước khi shouldSkip ghi key).
  static const _inFlightWindow = Duration(milliseconds: 900);

  static String _key({
    required String documentType,
    String? referenceId,
    String? referenceNo,
    String? printerId,
  }) {
    final ref = (referenceId?.trim().isNotEmpty == true)
        ? referenceId!.trim()
        : (referenceNo?.trim() ?? '');
    return '$documentType|$ref|${printerId ?? '*'}';
  }

  /// true = đang có lệnh in cùng key — bỏ qua (kèm toast ở caller).
  static bool shouldSkip({
    required String documentType,
    String? referenceId,
    String? referenceNo,
    String? printerId,
  }) {
    final ref = (referenceId?.trim().isNotEmpty == true)
        ? referenceId!.trim()
        : (referenceNo?.trim() ?? '');
    if (ref.isEmpty) return false;
    final key = _key(
      documentType: documentType,
      referenceId: referenceId,
      referenceNo: referenceNo,
      printerId: printerId,
    );
    final now = DateTime.now();

    final flight = _inFlightUntil[key];
    if (flight != null && flight.isAfter(now)) return true;

    final last = _recent[key];
    if (last != null && now.difference(last) < _window) return true;

    _recent[key] = now;
    _inFlightUntil[key] = now.add(_inFlightWindow);
    if (_recent.length > 200) {
      _recent.removeWhere((_, t) => now.difference(t) > _window);
    }
    if (_inFlightUntil.length > 200) {
      _inFlightUntil.removeWhere((_, t) => t.isBefore(now));
    }
    return false;
  }
}
