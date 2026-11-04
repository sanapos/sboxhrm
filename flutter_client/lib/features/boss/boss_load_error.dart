import 'package:flutter/material.dart';

import '../../config/sbox_app_variant.dart';
import '../../widgets/sbox/sbox_basics.dart';

/// Lỗi tải dữ liệu của màn BOSS: gói dịch vụ không có chức năng thì báo rõ, không gợi ý «Thử lại».
class BossLoadError extends StatelessWidget {
  const BossLoadError({super.key, required this.title, this.message, this.onRetry});

  final String title;
  final String? message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    if (SboxAppVariant.isPackageBlocked(message)) {
      return SboxEmptyState(
        icon: Icons.lock_outline_rounded,
        title: 'Chưa có trong gói dịch vụ',
        message: SboxAppVariant.rebrand(message!),
      );
    }
    return SboxEmptyState(
      icon: Icons.cloud_off_rounded,
      title: title,
      message: message,
      action: onRetry == null ? null : SboxButton(label: 'Thử lại', onPressed: onRetry),
    );
  }
}
