import 'package:flutter/material.dart';

import '../theme/sbox_tokens.dart';

/// Ô icon theo kiểu logo app: nền chuyển màu thương hiệu, biểu tượng trắng.
/// SBOX HRM: xanh dương của logo; POS / Nhân Viên: màu thương hiệu của app.
class SboxIconTile extends StatelessWidget {
  const SboxIconTile(this.icon, {super.key, this.size = 40, this.iconSize, this.radius});

  final IconData icon;
  final double size;
  final double? iconSize;
  final double? radius;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [SboxColors.iconTileLight, SboxColors.iconTileDark],
          ),
          borderRadius: BorderRadius.circular(radius ?? size * 0.3),
        ),
        child: Icon(icon, size: iconSize ?? size * 0.54, color: SboxColors.white),
      );
}
