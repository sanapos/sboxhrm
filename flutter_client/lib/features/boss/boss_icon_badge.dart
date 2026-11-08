import 'package:flutter/material.dart';

import '../../theme/sbox_tokens.dart';

/// Icon của SBOX BOSS theo logo: hình vàng trên ô bo góc xanh đen.
/// Truyền [color] (đỏ, cam) cho việc cần chú ý: khi đó hình màu trắng.
class BossIconBadge extends StatelessWidget {
  const BossIconBadge(this.icon, {super.key, this.size = 44, this.color});

  final IconData icon;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color,
          gradient: color != null
              ? null
              : const LinearGradient(
                  colors: [SboxColors.brand500, SboxColors.brand700],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
          borderRadius: BorderRadius.circular(size * 0.3),
        ),
        child: Icon(icon, size: size * 0.54, color: color == null ? SboxColors.gold : SboxColors.white),
      );
}
