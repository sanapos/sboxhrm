import 'package:flutter/foundation.dart';

import 'settings_hub_catalog.dart';

/// Mục Thiết lập SBOX sẽ mở thẳng khi điều hướng tới trang Thiết lập.
///
/// Tách khỏi `SettingsHubScreen` để nơi điều hướng (`NavigationNotifier`) không phải nạp cả màn Thiết lập —
/// màn đó import 12 màn chấm công / lương, kéo theo cả phần HRM vào gói SBOX Bán Hàng (Apple 2.5.19).
abstract final class SettingsHubPending {
  /// Đặt giá trị kể cả khi đang ở trang Thiết lập; màn Thiết lập theo dõi và mở mục tương ứng.
  static final ValueNotifier<int?> subIndex = ValueNotifier<int?>(null);

  /// Mở thẳng một mục theo mã chữ cố định (vd `printers`, `printTemplates`, `device`).
  /// Gọi trước khi điều hướng tới Thiết lập SBOX. Trả về false nếu mã không tồn tại.
  static bool openCode(String code) {
    final item = SettingsHubCatalog.byCode(code);
    if (item == null) return false;
    subIndex.value = item.index;
    return true;
  }
}
