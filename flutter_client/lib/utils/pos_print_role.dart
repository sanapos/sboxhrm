import 'pos_print_agent_settings.dart';

/// Phân vai in cloud: thiết bị gắn máy in (Agent) vs thiết bị gửi lệnh từ xa.
abstract final class PosPrintRole {
  static String _normId(String id) => id.trim().toLowerCase();

  /// So khớp GUID máy in (không phân biệt hoa/thường).
  static bool matchesPrinterId(String a, String b) =>
      _normId(a) == _normId(b);

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
  static const _window = Duration(seconds: 25);

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
    final key = '$documentType|$ref|${printerId ?? '*'}';
    final now = DateTime.now();
    final last = _recent[key];
    if (last != null && now.difference(last) < _window) return true;
    _recent[key] = now;
    if (_recent.length > 200) {
      _recent.removeWhere((_, t) => now.difference(t) > _window);
    }
    return false;
  }
}
