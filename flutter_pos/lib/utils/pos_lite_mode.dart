import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

/// Chế độ gọn cho máy Android 6 (Sunmi T1 A6) — chủ yếu quán cà phê / quán ăn có order:
/// ẩn báo giá, hợp đồng, HĐĐT, hội viên và thiết lập nhân sự (làm trên web / SBOX HRM);
/// bán hàng, kho, báo cáo, thu chi, máy in, màn hình phụ giữ đủ.
/// Máy Android 7+ (V2s, A7…) dùng cùng APK vẫn đủ chức năng.
class PosLiteMode {
  PosLiteMode._();

  /// `--dart-define=SBOX_POS_LITE=true|false` ép bật / tắt (thử trên máy khác).
  static const _force = String.fromEnvironment('SBOX_POS_LITE');

  static bool enabled = false;

  static Future<void> init() async {
    if (_force.isNotEmpty) {
      enabled = _force == 'true';
      return;
    }
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      enabled = info.version.sdkInt < 24;
    } catch (e) {
      debugPrint('PosLiteMode: $e');
    }
  }

  /// Mục ẩn trong «Nhiều hơn» (báo giá / hợp đồng / HĐĐT / hội viên làm trên web hoặc SBOX HRM).
  /// Kho, nhập hàng, báo cáo, thu chi vẫn giữ — chủ quán cần xem / làm ngay tại quầy.
  static const hiddenMoreItems = {
    'Báo giá',
    'Hợp đồng',
    'Mẫu in báo giá',
    'Hóa đơn điện tử',
    'Check-in hội viên',
    'Tra cứu BH',
  };

  /// Mục giữ lại trong «Thiết lập SBOX».
  static const settingsItems = {
    'Thông tin cửa hàng',
    'Ngành hàng & cách bán',
    'Bàn / phòng',
    'Tài khoản nhận tiền',
    'Máy in',
    'Mẫu in',
    'Màn hình phụ',
    'Thông báo',
  };

  static bool showMore(String label) => !enabled || !hiddenMoreItems.contains(label);
  static bool showSetting(String label) => !enabled || settingsItems.contains(label);
}
