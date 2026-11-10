import 'package:flutter/widgets.dart';

import '../utils/app_fullscreen.dart';
import '../utils/responsive_helper.dart';

/// Giới hạn bề rộng nội dung trang (đặt trong [Center]).
///
/// - Bình thường: tối đa [normal] (mặc định [Responsive.pageMaxWidth]) — màn 1920px+ không kéo
///   thẻ / bảng quá dài.
/// - «Toàn màn hình» ([AppFullscreen]): bỏ giới hạn, nội dung trải hết bề ngang.
///
/// Dùng cho thân trang danh sách / bảng / lưới. Hộp thoại và biểu mẫu nhập liệu giữ bề rộng
/// riêng (kéo rộng ra khó đọc).
class PageMaxWidth extends StatelessWidget {
  const PageMaxWidth({
    super.key,
    required this.child,
    this.normal = Responsive.pageMaxWidth,
  });

  final double normal;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: AppFullscreen.active,
      builder: (context, fullscreen, child) => ConstrainedBox(
        constraints: BoxConstraints(maxWidth: fullscreen ? double.infinity : normal),
        child: child,
      ),
      child: child,
    );
  }
}
