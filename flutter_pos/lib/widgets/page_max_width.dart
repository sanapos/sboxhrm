import 'package:flutter/widgets.dart';

import '../utils/responsive_helper.dart';

/// Giới hạn bề rộng nội dung trang (đặt trong [Center]) — bản flutter_client có thêm chế độ
/// «Toàn màn hình»; SBOX POS Android 6 không có nên chỉ giữ giới hạn thường.
class PageMaxWidth extends StatelessWidget {
  const PageMaxWidth({
    super.key,
    required this.child,
    this.normal = Responsive.pageMaxWidth,
  });

  final double normal;
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      ConstrainedBox(constraints: BoxConstraints(maxWidth: normal), child: child);
}
