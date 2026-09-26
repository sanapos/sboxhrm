import 'dart:convert';

/// Mã vạch cân điện tử (EAN-13 nội bộ, đầu 20–29): [đầu 2 số][mã hàng PLU][giá trị][số kiểm tra].
/// Giá trị là trọng lượng (gram → kg) hoặc thành tiền, tùy cấu hình cân.
class PosScaleBarcode {
  final String plu;
  final double value;
  final bool isWeight;
  const PosScaleBarcode(this.plu, this.value, this.isWeight);
}

/// Cấu hình trong PosStoreSellSettings.ExtraJson → "scale".
class PosScaleBarcodeConfig {
  final bool enabled;
  final List<String> prefixes;
  final int pluDigits;
  /// "weight" (trọng lượng) hoặc "price" (thành tiền).
  final String mode;
  /// Số lẻ thập phân của giá trị: trọng lượng gram → 3 (kg); giá tiền → 0.
  final int decimals;

  const PosScaleBarcodeConfig({
    this.enabled = false,
    this.prefixes = const ['20', '21', '22', '23', '24', '25', '26', '27', '28', '29'],
    this.pluDigits = 5,
    this.mode = 'weight',
    this.decimals = 3,
  });

  bool get isWeight => mode != 'price';

  static PosScaleBarcodeConfig parse(String? extraJson) {
    const d = PosScaleBarcodeConfig();
    if (extraJson == null || extraJson.trim().isEmpty) return d;
    try {
      final root = jsonDecode(extraJson);
      final s = root is Map ? (root['scale'] ?? root['Scale']) : null;
      if (s is! Map) return d;
      final pre = s['prefixes'];
      final plu = s['pluDigits'];
      final dec = s['decimals'];
      final mode = s['mode']?.toString() == 'price' ? 'price' : 'weight';
      return PosScaleBarcodeConfig(
        enabled: s['enabled'] == true,
        prefixes: pre is List
            ? pre.map((e) => e.toString().trim()).where((e) => RegExp(r'^\d{1,2}$').hasMatch(e)).toList()
            : d.prefixes,
        pluDigits: plu is num && plu >= 4 && plu <= 6 ? plu.toInt() : d.pluDigits,
        mode: mode,
        decimals: dec is num && dec >= 0 && dec <= 3 ? dec.toInt() : (mode == 'price' ? 0 : 3),
      );
    } catch (_) {
      return d;
    }
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'prefixes': prefixes,
        'pluDigits': pluDigits,
        'mode': mode,
        'decimals': decimals,
      };

  PosScaleBarcodeConfig copyWith({bool? enabled, List<String>? prefixes, int? pluDigits, String? mode}) {
    final m = mode ?? this.mode;
    return PosScaleBarcodeConfig(
      enabled: enabled ?? this.enabled,
      prefixes: prefixes ?? this.prefixes,
      pluDigits: pluDigits ?? this.pluDigits,
      mode: m,
      decimals: mode == null ? decimals : (m == 'price' ? 0 : 3),
    );
  }

  /// Ghi đè khóa "scale" trong ExtraJson, giữ các khóa khác.
  String mergeIntoExtraJson(String? extraJson) {
    Map<String, dynamic> root = {};
    try {
      final r = extraJson == null || extraJson.trim().isEmpty ? null : jsonDecode(extraJson);
      if (r is Map) root = Map<String, dynamic>.from(r);
    } catch (_) {}
    root.remove('Scale');
    root['scale'] = toJson();
    return jsonEncode(root);
  }

  /// null khi không phải mã cân (tắt, sai độ dài, sai đầu mã, sai số kiểm tra).
  PosScaleBarcode? decode(String code) {
    if (!enabled) return null;
    final c = code.trim();
    if (c.length != 13 || !RegExp(r'^\d{13}$').hasMatch(c)) return null;
    if (!prefixes.any(c.startsWith)) return null;
    if (!_validEan13(c)) return null;
    final plu = c.substring(2, 2 + pluDigits);
    final raw = int.tryParse(c.substring(2 + pluDigits, 12));
    if (raw == null || raw <= 0) return null;
    var div = 1;
    for (var i = 0; i < decimals; i++) {
      div *= 10;
    }
    return PosScaleBarcode(plu, raw / div, isWeight);
  }

  static bool _validEan13(String c) {
    var sum = 0;
    for (var i = 0; i < 12; i++) {
      sum += (c.codeUnitAt(i) - 48) * (i.isEven ? 1 : 3);
    }
    return (10 - sum % 10) % 10 == c.codeUnitAt(12) - 48;
  }
}
