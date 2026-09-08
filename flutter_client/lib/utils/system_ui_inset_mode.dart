import 'package:flutter/foundation.dart';

/// POS «Phóng toàn màn hình»: ẩn status/nav — [padAwaySystemBars] không chừa fallback.
class SystemUiInsetMode {
  SystemUiInsetMode._();

  static final ValueNotifier<bool> immersive = ValueNotifier<bool>(false);
}
