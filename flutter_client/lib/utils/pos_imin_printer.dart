import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Thông tin máy iMin do `IminPrinterBridge.kt` trả về.
class PosIminInfo {
  const PosIminInfo({
    required this.isImin,
    required this.sdk,
    required this.model,
    required this.buildModel,
    required this.connectType,
  });

  static const none = PosIminInfo(
    isImin: false,
    sdk: 0,
    model: '',
    buildModel: '',
    connectType: '',
  );

  final bool isImin;

  /// 1 = SDK 1.0 (Android ≤ 11), 2 = SDK 2.0 (Android 12L+), 0 = không phải iMin.
  final int sdk;

  /// Model iMin (`ro.neostra.imin_model`, vd. "D4-503", "M2-202", "Swan 2").
  final String model;
  final String buildModel;

  /// USB / SPI (SDK 1.0) hoặc SERVICE (SDK 2.0).
  final String connectType;

  factory PosIminInfo.fromMap(Map<Object?, Object?> m) => PosIminInfo(
        isImin: m['isImin'] == true,
        sdk: (m['sdk'] as num?)?.toInt() ?? 0,
        model: (m['model'] as String?) ?? '',
        buildModel: (m['buildModel'] as String?) ?? '',
        connectType: (m['connectType'] as String?) ?? '',
      );

  /// Máy cầm tay khổ 58mm (M2 / Swift, không dao cắt). Máy để bàn (D1/D4/Swan/Falcon/Crane) mặc định 80mm.
  bool get looksLike58mm {
    final m = '$model $buildModel'.toLowerCase();
    return m.contains('m2') || m.contains('swift') || m.contains('ms1');
  }
}

/// Kết quả một lần in qua máy in iMin.
class PosIminPrintResult {
  const PosIminPrintResult(this.ok, this.status);
  final bool ok;

  /// Mã trạng thái iMin (xem [PosIminPrinter.statusMessage]); -1 = không đọc được.
  final int status;
}

/// Cầu nối Dart → `IminPrinterBridge.kt` (kênh `com.sboxhrm/imin_printer`).
///
/// SDK iMin chỉ khởi tạo ở phía Android khi máy đúng là iMin và có lệnh in/trạng thái,
/// nên gọi [info] trên Sunmi / điện thoại là an toàn.
class PosIminPrinter {
  PosIminPrinter._();

  static const MethodChannel _ch = MethodChannel('com.sboxhrm/imin_printer');

  /// Cho phép test thay thế kênh.
  @visibleForTesting
  static MethodChannel get channel => _ch;

  static PosIminInfo? _info;

  /// Test chạy trên máy dev (Windows): coi như Android để đi qua kênh giả lập.
  @visibleForTesting
  static bool debugAssumeAndroid = false;

  @visibleForTesting
  static void resetCache() => _info = null;

  static Future<PosIminInfo> info() async {
    final cached = _info;
    if (cached != null) return cached;
    if (kIsWeb || (!Platform.isAndroid && !debugAssumeAndroid)) {
      return _info = PosIminInfo.none;
    }
    try {
      final m = await _ch
          .invokeMethod<Map<Object?, Object?>>('info')
          .timeout(const Duration(seconds: 3));
      return _info = m == null ? PosIminInfo.none : PosIminInfo.fromMap(m);
    } catch (e) {
      debugPrint('iMin info: $e');
      return _info = PosIminInfo.none;
    }
  }

  /// Mã trạng thái; -1 khi lỗi / không đọc được.
  static Future<int> status() async {
    try {
      final v = await _ch
          .invokeMethod<int>('status')
          .timeout(const Duration(seconds: 8));
      return v ?? -1;
    } catch (e) {
      debugPrint('iMin status: $e');
      return -1;
    }
  }

  /// Gửi ESC/POS thô. [openDrawer]: mở két bằng API iMin (SDK 1.0 không nhận ESC p qua GPIO).
  static Future<PosIminPrintResult> printBytes(
    List<int> bytes, {
    bool openDrawer = false,
  }) async {
    try {
      final m = await _ch.invokeMethod<Map<Object?, Object?>>('print', {
        'bytes': Uint8List.fromList(bytes),
        'openDrawer': openDrawer,
      }).timeout(const Duration(seconds: 40));
      return PosIminPrintResult(
        m?['ok'] == true,
        (m?['status'] as num?)?.toInt() ?? -1,
      );
    } catch (e) {
      debugPrint('iMin print: $e');
      return const PosIminPrintResult(false, -1);
    }
  }

  static Future<bool> openDrawer() async {
    try {
      return await _ch
              .invokeMethod<bool>('openDrawer')
              .timeout(const Duration(seconds: 8)) ??
          false;
    } catch (e) {
      debugPrint('iMin drawer: $e');
      return false;
    }
  }

  /// Khổ giấy (58 / 80) cho máy này: SDK 2.0 hỏi máy in, không rõ thì đoán theo model.
  static Future<int> paperWidthMm() async {
    final i = await info();
    if (!i.isImin) return 80;
    if (i.sdk == 2) {
      try {
        final m = await _ch
            .invokeMethod<Map<Object?, Object?>>('paperInfo')
            .timeout(const Duration(seconds: 8));
        final mm = paperMmFromSdk(
          (m?['type'] as num?)?.toInt() ?? -1,
          [for (final t in (m?['types'] as List?) ?? const []) '$t'],
        );
        if (mm != null) return mm;
      } catch (e) {
        debugPrint('iMin paperInfo: $e');
      }
    }
    return i.looksLike58mm ? 58 : 80;
  }

  /// Suy khổ từ `getPrinterPaperType` + `getPrinterPaperTypeList` (SDK 2.0).
  /// Tài liệu iMin không ghi ý nghĩa giá trị: ưu tiên chuỗi trong danh sách có «58»/«80».
  @visibleForTesting
  static int? paperMmFromSdk(int type, List<String> types) {
    String? label;
    if (type >= 0 && type < types.length) label = types[type];
    if (label == null && types.length == 1) label = types.first;
    if (label != null) {
      if (label.contains('58')) return 58;
      if (label.contains('80')) return 80;
    }
    return null;
  }

  /// Lời nhắn tiếng Việt cho mã trạng thái iMin (null = in được).
  static String? statusMessage(int code) {
    switch (code) {
      case 0:
      case 8:
      case -1:
        return null;
      case 1:
        return 'Máy in iMin chưa kết nối / chưa bật';
      case 3:
        return 'Máy in iMin đang mở nắp';
      case 4:
        return 'Dao cắt máy in iMin bị kẹt';
      case 5:
        return 'Đầu in iMin quá nóng';
      case 7:
        return 'Máy in iMin hết giấy';
      default:
        return 'Máy in iMin báo lỗi ($code)';
    }
  }
}
