import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

/// Chế độ gọn cho máy Android 6 (Sunmi T1 A6) — chủ yếu quán cà phê / quán ăn có order:
/// chỉ giữ bán hàng, order bàn / QR, bếp, ca thu ngân, máy in (thiết bị + cloud), màn hình phụ,
/// khách hàng và vài báo cáo hằng ngày. Báo giá, hợp đồng, kho, thiết lập sâu làm trên web / SBOX HRM.
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

  /// Mục giữ lại trong «Nhiều hơn».
  static const moreItems = {
    'Bán hàng',
    'Hoá đơn',
    'Trả hàng bán',
    'Lịch sử hủy / trả',
    'Cuối ngày',
    'Ca thu ngân',
    'QR order bàn',
    'Menu QR / Online',
    'Đơn online',
    'Xác nhận CK',
    'Màn hình bếp (KDS)',
    'Hàng hoá',
    'Khách hàng',
    'Công nợ KH',
    'Thiết lập SBOX',
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

  /// Báo cáo giữ lại.
  static const reports = {
    'Doanh thu',
    'Hàng hóa bán ra',
    'Phương thức thanh toán',
    'Tổng kết cuối ngày',
    'Doanh thu theo nhân viên',
    'Sổ quỹ',
  };

  static bool showMore(String label) => !enabled || moreItems.contains(label);
  static bool showSetting(String label) => !enabled || settingsItems.contains(label);
  static bool showReport(String label) => !enabled || reports.contains(label);
}
